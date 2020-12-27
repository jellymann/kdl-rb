module KDL
  class Tokenizer
    class Error < StandardError; end

    attr_reader :index

    SYMBOLS = {
      '{' => :LPAREN,
      '}' => :RPAREN,
      '=' => :EQUALS,
      '＝' => :EQUALS,
      ';' => :SEMICOLON
    }

    WHITEPACE = ["\u0009", "\u0020", "\u00A0", "\u1680",
                 "\u2000", "\u2001", "\u2002", "\u2003",
                 "\u2004", "\u2005", "\u2006", "\u2007",
                 "\u2008", "\u2009", "\u200A", "\u202F",
                 "\u205F", "\u3000" ]

    NEWLINES = ["\u000A", "\u0085", "\u000C", "\u2028", "\u2029"]

    NON_IDENTIFIER_CHARS = Regexp.escape "#{SYMBOLS.keys.join('')}\\<>[]\","
    IDENTIFIER_CHARS = /[^#{NON_IDENTIFIER_CHARS}\x0-\x20]/
    INITIAL_IDENTIFIER_CHARS = /[^#{NON_IDENTIFIER_CHARS}0-9\x0-\x20]/

    def initialize(str, start = 0)
      @str = str
      @context = nil
      @rawstring_hashes = nil
      @index = start
      @buffer = ""
      @done = false
      @previous_context = nil
    end

    def next_token
      @context = nil
      @previous_context = nil
      loop do
        c = @str[@index]
        case @context
        when nil
          case c
          when '"'
            self.context = :string
            @buffer = ''
            @index += 1
          when 'r'
            if @str[@index + 1] == '"'
              self.context = :rawstring
              @index += 2
              @rawstring_hashes = 0
              @buffer = ''
              next
            elsif @str[@index + 1] == '#'
              i = @index + 1
              @rawstring_hashes = 0
              while @str[i] == '#'
                @rawstring_hashes += 1
                i += 1
              end
              if @str[i] == '"'
                self.context = :rawstring
                @index = i + 1
                @buffer = ''
                next
              end
            end
            self.context = :ident
            @buffer = c
            @index += 1
          when /[0-9\-+]/
            n = @str[@index + 1]
            if c == '0' && n.match?(/[box]/)
              @index += 2
              @buffer = ''
              self.context = case n
                         when 'b' then :binary
                         when 'o' then :octal
                         when 'x' then :hexadecimal
                         end
            else
              self.context = :decimal
              @index += 1
              @buffer = c
            end
          when '\\'
            t = Tokenizer.new(@str, @index + 1)
            la = t.next_token[0]
            if la == :NEWLINE || (la == :WS && t.next_token[0] == :NEWLINE)
              @index = t.index
            else
              raise Error, "Unexpected '\\'"
            end
          when *SYMBOLS.keys
            @index += 1
            return [SYMBOLS[c], c]
          when "\r"
            n = @str[@index + 1]
            if n == "\n"
              @index += 2
              return [:NEWLINE, "#{c}#{n}"]
            else
              @index += 1
              return [:NEWLINE, c]
            end
          when *NEWLINES
            @index += 1
            return [:NEWLINE, c]
          when "/"
            if @str[@index + 1] == '/'
              self.context = :single_line_comment
              @index += 2
            elsif @str[@index + 1] == '*'
              self.context = :multi_line_comment
              @comment_nesting = 1
              @index += 2
            elsif @str[@index + 1] == '-'
              @index += 2
              return [:SLASHDASH, '/-']
            else
              self.context = :ident
              @buffer = c
              @index += 1
            end
          when *WHITEPACE
            self.context = :whitespace
            @buffer = c
            @index += 1
          when nil
            return [false, false] if @done
            @done = true
            return [:EOF, '']
          when INITIAL_IDENTIFIER_CHARS
            self.context = :ident
            @buffer = c
            @index += 1
          else
            raise Error, "Unexpected character #{c.inspect}"
          end
        when :ident
          case c
          when IDENTIFIER_CHARS
            @index += 1
            @buffer += c
          else
            case @buffer
            when 'true'  then return [:TRUE, true]
            when 'false' then return [:FALSE, false]
            when 'null'  then return [:NULL, nil]
            else return [:IDENT, @buffer]
            end
          end
        when :string
          case c
          when '\\'
            @buffer += c
            @buffer += @str[@index + 1]
            @index += 2
          when '"'
            @index += 1
            return [:STRING, convert_escapes(@buffer)]
          when nil
            raise Error, "Unterminated string literal"
          else
            @buffer += c
            @index += 1
          end
        when :rawstring
          raise Error, "Unterminated rawstring literal" if c.nil?

          if c == '"'
            h = 0
            while @str[@index + 1 + h] == '#' && h < @rawstring_hashes
              h += 1
            end
            if h == @rawstring_hashes
              @index += 1 + h
              return [:RAWSTRING, @buffer]
            end
          end

          @buffer += c
          @index += 1
        when :decimal
          case c
          when /[0-9.\-+_eE]/
            @index += 1
            @buffer += c
          else
            return parse_decimal(@buffer)
          end
        when :hexadecimal
          case c
          when /[0-9a-fA-F_]/
            @index += 1
            @buffer += c
          else
            return parse_hexadecimal(@buffer)
          end
        when :octal
          case c
          when /[0-7_]/
            @index += 1
            @buffer += c
          else
            return parse_octal(@buffer)
          end
        when :binary
          case c
          when /[01_]/
            @index += 1
            @buffer += c
          else
            return parse_binary(@buffer)
          end
        when :single_line_comment
          @index += 1
          if c == "\n"
            return [:NEWLINE, c]
          elsif c.nil?
            @done = true
            return [:EOF, '']
          end
        when :multi_line_comment
          if c == '/' && @str[@index + 1] == '*'
            @comment_nesting += 1
            @index += 2
          elsif c == '*' && @str[@index + 1] == '/'
            @comment_nesting -= 1
            @index += 2
            if @comment_nesting == 0
              revert_context
            end
          else
            @index += 1
          end
        when :whitespace
          if WHITEPACE.include?(c)
            @index += 1
            @buffer += c
          elsif c == "\\"
            t = Tokenizer.new(@str, @index + 1)
            la = t.next_token[0]
            if la == :NEWLINE || (la == :WS && t.next_token[0] == :NEWLINE)
              @index = t.index
            else
              raise Error, "Unexpected '\\'"
            end
          elsif c == "/" && @str[@index + 1] == '*'
            self.context = :multi_line_comment
            @comment_nesting = 1
            @index += 2
          else
            return [:WS, @buffer]
          end
        end
      end
    end

    def context=(val)
      @previous_context = @context
      @context = val
    end

    def revert_context
      @context = @previous_context
      @previous_context = nil
    end

    private

    def parse_decimal(s)
      return [:FLOAT, Float(s)] if s.match?(/[.eE]/)
      [:INTEGER, Integer(s)]
    end
    
    def parse_hexadecimal(s)
      [:INTEGER, Integer(s, 16)]
    end
    
    def parse_octal(s)
      [:INTEGER, Integer(s, 8)]
    end
    
    def parse_binary(s)
      [:INTEGER, Integer(s, 2)]
    end

    def convert_escapes(string)
      string.gsub(/\\./) do |m|
        case m
        when '\n' then "\n"
        when '\r' then "\r"
        when '\t' then "\t"
        when '\\\\' then "\\"
        when '\"' then "\""
        when '\b' then "\b"
        when '\f' then "\f"
        else m[1]
        end
      end
      # TODO: unicode char codes, e.g. \\u[0-9a-fA-F]{0,6}
    end
  end
end

require "test_helper"

class ValueTest < Minitest::Test
  def test_to_s
    assert_equal "1", ::KDL::Value::Int.new(1).to_s
    assert_equal "1.5", ::KDL::Value::Float.new(1.5).to_s
    assert_equal "true", ::KDL::Value::Boolean.new(true).to_s
    assert_equal "false", ::KDL::Value::Boolean.new(false).to_s
    assert_equal "null", ::KDL::Value::Null.to_s
    assert_equal '"foo"', ::KDL::Value::String.new("foo").to_s
    assert_equal '"foo \"bar\" baz"', ::KDL::Value::String.new('foo "bar" baz').to_s
  end

  def test_from
    assert_equal(KDL::Value::Int.new(1), KDL::Value::from(1))
    assert_equal(KDL::Value::Float.new(1.5), KDL::Value::from(1.5))
    assert_equal(
      KDL::Value::String.new("foo"),
      KDL::Value::from("foo")
    )
    assert_equal(KDL::Value::String.new("bar"), KDL::Value::from("bar"))
    assert_equal(KDL::Value::Boolean.new(true), KDL::Value::from(true))

    assert_equal(KDL::Value::Null, KDL::Value::from(nil))
  end
end

require "#{File.expand_path(File.dirname(__FILE__))}/test_helper"

class SqlParserTest < ActiveSupport::TestCase
  include GoogleDataSource::DataSource

  test "quoting with ticks" do
    result = SqlParser.parse("where `foo bar`=3")
    assert_equal 'foo bar', result.where.left.to_s
  end

  test "quoting with single quotes" do
    result = SqlParser.parse("where bar='foo bar'")
    assert_equal 'foo bar', result.where.right.to_s
  end

  test "allow escaped quotes in qutoed strings" do
    result = SqlParser.parse("where bar='test\\''")
    assert_equal "test'", result.where.right.to_s
  end

  test "allow escaped backslash" do
    result = SqlParser.parse("where bar='te\\\\st'")
    assert_equal "te\\st", result.where.right.to_s
  end

  test "allow escaped backslash as last character" do
    result = SqlParser.parse("where bar='test\\\\'")
    assert_equal "test\\", result.where.right.to_s
  end

  test "parsing of empty single quoted string ('')" do
    result = SqlParser.parse("where foo=''")
    assert_equal "", result.where.right.to_s
  end

  test "the 'in' statement in where conditions" do
    result = SqlParser.parse("where foo in ('1','2')")
    assert_equal "foo", result.where.expr.to_s
    assert_equal 2, result.where.vals.size
    assert_equal '1', result.where.vals[0].to_s
    assert_equal '2', result.where.vals[1].to_s
  end

  ###############################
  # Test the simple parser
  ###############################
  test "simple parser" do
    result = SqlParser.simple_parse("select id,name where age = 18 group by attr1, attr2 order by age asc limit 10 offset 5")
    assert_equal ['id', 'name'], result.select
    assert_equal 10, result.limit
    assert_equal 5, result.offset
    assert_equal ['attr1', 'attr2'], result.groupby
    assert_equal ['age', :asc], result.orderby
    assert_equal({'age' => '18'}, result.conditions)
  end

  test "simple order parser should only accept a single ordering" do
    assert_raises GoogleDataSource::DataSource::SimpleSqlException do
      SqlParser.simple_parse("order by name,date")
    end
  end

  test "simple groupby parser should return empty array if no group by statement is given" do
    assert_equal [], SqlParser.simple_parse("").groupby
  end

  test "simple where parser" do
    conditions = SqlParser.simple_parse("where id = 1 and name = `foo bar` and `foo bar` = 123").conditions

    assert_equal '1', conditions['id']
    assert_equal 'foo bar', conditions['name']
    assert_equal '123', conditions['foo bar']
  end

  test "simple where parser should only accept and operators" do
    assert_raises GoogleDataSource::DataSource::SimpleSqlException do
      SqlParser.simple_parse("where id = 1 or name = `foo bar`")
    end
  end

  test "where parser should convert other operators than = to array" do
    conditions = SqlParser.simple_parse("where date > '2010-01-01' and date < '2010-02-01'").conditions
    assert_kind_of Array, conditions['date']
    assert_equal '>', conditions['date'].first.op
    assert_equal '2010-01-01', conditions['date'].first.value
    assert_equal '<', conditions['date'].last.op
    assert_equal '2010-02-01', conditions['date'].last.value
  end

  test "limit should be nil if empty in query" do
    assert_nil SqlParser.simple_parse("").limit
  end

  test "offset should be nil if empty in query" do
    assert_nil SqlParser.simple_parse("").offset
  end

  test "raise exception if operator = is used besides of other operators in where clause" do
    assert_raise GoogleDataSource::DataSource::SimpleSqlException do
      SqlParser.simple_parse("where foo = '1' and foo >= 2")
    end
  end

  test "parsing in( ) expressions in where clause" do
    conditions = SqlParser.simple_parse("where foo in ('1','2')").conditions
    assert_equal 1, conditions['foo'].size
    assert_equal 'in', conditions['foo'].first.op
    assert_equal %w(1 2), conditions['foo'].first.value
  end
end

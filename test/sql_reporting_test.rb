require "#{File.expand_path(File.dirname(__FILE__))}/test_helper"

class SqlReportingTest < ActiveSupport::TestCase
  class TestReporting < SqlReporting
    attr_reader :aggregate_calls
    filter :name

    table :notneeded,                         :join => 'JOIN notneeded'
    table :buildings, :depends => :companies, :join => 'JOIN buildings'
    table :companies,                         :join => 'JOIN companies'

    column :firstname,    :type => :string, :sql => true
    column :lastname,     :type => :string, :sql => { :column => :name }
    column :company_name, :type => :string, :sql => { :table => :companies, :column => :name }
    column :fullname,     :type => :string
    column :building_no,  :type => :number, :sql => { :table => :buildings, :column => :number }

    def initialize(*args)
      @aggregate_calls = 0
      super(*args)
    end

    def aggregate
      @aggregate_calls += 1
      @rows = []
    end
  end

  def setup
    @reporting = TestReporting.new
  end

  test "is_sql_column?" do
    assert @reporting.is_sql_column?(:firstname)
    assert @reporting.is_sql_column?('lastname')
    assert !@reporting.is_sql_column?(:fullname)
  end

  test "sql_column_name" do
    assert !@reporting.sql_column_name(:fullname)
    assert_equal 'firstname', @reporting.sql_column_name(:firstname)
    assert_equal 'firstname', @reporting.sql_column_name(:firstname, :with_alias => true)
    assert_equal 'name', @reporting.sql_column_name(:lastname)
    assert_equal 'companies.name', @reporting.sql_column_name(:company_name)
    assert_equal 'companies.name company_name', @reporting.sql_column_name(:company_name, :with_alias => true)
  end

  test "select should consider mapping" do
    @reporting.select = %w(firstname)
    assert_equal 'christian_name firstname', @reporting.sql_select([], 'firstname' => 'christian_name')
  end

  test "group_by should consider mapping" do
    @reporting.group_by = %w(firstname)
    assert_equal 'christian_name', @reporting.sql_group_by([], 'firstname' => 'christian_name')
  end

  test "select some sql and some ruby columns" do
    reporting = reporting_from_query("select firstname, fullname")
    assert_equal "firstname", reporting.sql_select
  end

  test "use column name mappings in sql_select" do
    reporting = reporting_from_query("select company_name, fullname")
    assert_equal "companies.name company_name", reporting.sql_select
  end

  test "sql_columns" do
    assert @reporting.sql_columns.include?(:firstname)
    assert @reporting.sql_columns.include?(:company_name)
    assert !@reporting.sql_columns.include?(:fullname)
  end

  test "select *" do
    reporting = reporting_from_query("select *")
    sql = reporting.sql_columns.collect { |c| reporting.sql_column_name(c, :with_alias => true) }.join (', ')
    assert_equal sql, reporting.sql_select
  end

  test "sql_group_by" do
    reporting = reporting_from_query("group by firstname, fullname")
    assert_equal "firstname", reporting.sql_group_by
  end

  test "sql_group_by should be nil if no grouping exists" do
    reporting = reporting_from_query("")
    assert_nil reporting.sql_group_by
  end

  test "sql_order_by" do
    reporting = reporting_from_query("order by firstname")
    assert_equal "firstname ASC", reporting.sql_order_by
  end

  test "sql_order_by shoul dconsider mapping" do
    reporting = reporting_from_query("order by firstname")
    assert_equal "name ASC", reporting.sql_order_by('firstname' => 'name')
  end

  test "sql_order_by should return nil if order_by is not set" do
    reporting = reporting_from_query("")
    assert_nil reporting.sql_order_by
  end

  test "use column name mappings in sql_group_by" do
    reporting = reporting_from_query("group by firstname, lastname, fullname")
    assert_equal "firstname, name", reporting.sql_group_by
  end

  test "get joins for columns" do
    assert_equal "", @reporting.sql_joins(%w(firstname))
    assert_equal "JOIN companies", @reporting.sql_joins(%w(company_name))
  end

  test "get joins resolving dependencies" do
    assert_equal "JOIN companies JOIN buildings", @reporting.sql_joins(%w(building_no company_name))
  end

  test "columns method should return plain columns without sql option" do
    reporting = reporting_from_query("select *")
    reporting.columns.each do |column|
      assert !column.has_key?(:sql)
    end
  end

  test "join according to the used columns" do
    reporting = reporting_from_query("select firstname")
    assert_equal "", reporting.sql_joins

    reporting = reporting_from_query("select company_name")
    reporting.sql_select
    assert_equal "JOIN companies", reporting.sql_joins
  end

  test "join if columns are added with mark_as_used" do
    reporting = reporting_from_query("select firstname")
    assert_equal "", reporting.sql_joins
    reporting.mark_as_used('company_name')
    assert_equal "JOIN companies", reporting.sql_joins
  end

  test "include required columns in sql_select statement" do
    reporting = reporting_from_query("select firstname")
    reporting.set_required_columns 'firstname', [:company_name]
    select = reporting.sql_select.split(', ')
    assert_equal 2, select.size
    assert select.include?('firstname')
    assert select.include?('companies.name company_name')
  end

  test "include joins for required columns" do
    reporting = reporting_from_query("select firstname")
    reporting.set_required_columns 'firstname', [:company_name]
    assert_equal "JOIN companies", reporting.sql_joins
  end

  def reporting_from_query(query)
    TestReporting.from_params({:tq => query})
  end
end

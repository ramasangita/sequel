require File.join(File.dirname(File.expand_path(__FILE__)), "spec_helper")

begin
  require 'active_support/duration'
rescue LoadError => e
  skip_warn "pg_interval plugin: can't load active_support/duration (#{e.class}: #{e})"
else
describe "pg_interval extension" do
  before do
    @db = Sequel.connect('mock://postgres', :quote_identifiers=>false)
    @db.extend(Module.new{def bound_variable_arg(arg, conn) arg end})
    @db.extension(:pg_array, :pg_interval)
  end

  it "should literalize ActiveSupport::Duration instances to strings correctly" do
    @db.literal(ActiveSupport::Duration.new(0, [])).should == "'0'::interval"
    @db.literal(ActiveSupport::Duration.new(0, [[:seconds, 0]])).should == "'0'::interval"
    @db.literal(ActiveSupport::Duration.new(0, [[:seconds, 10], [:minutes, 20], [:days, 3], [:months, 4], [:years, 6]])).should == "'6 years 4 months 3 days 20 minutes 10 seconds '::interval"
    @db.literal(ActiveSupport::Duration.new(0, [[:seconds, -10.000001], [:minutes, -20], [:days, -3], [:months, -4], [:years, -6]])).should == "'-6 years -4 months -3 days -20 minutes -10.000001 seconds '::interval"
  end

  it "should literalize ActiveSupport::Duration instances with repeated parts correctly" do
    @db.literal(ActiveSupport::Duration.new(0, [[:seconds, 2], [:seconds, 1]])).should == "'3 seconds '::interval"
    @db.literal(ActiveSupport::Duration.new(0, [[:seconds, 2], [:seconds, 1], [:days, 1], [:days, 4]])).should == "'5 days 3 seconds '::interval"
  end

  it "should not affect literalization of custom objects" do
    o = Object.new
    def o.sql_literal(ds) 'v' end
    @db.literal(o).should == 'v'
  end

  it "should support using ActiveSupport::Duration instances as bound variables" do
    @db.bound_variable_arg(1, nil).should == 1
    @db.bound_variable_arg(ActiveSupport::Duration.new(0, [[:seconds, 0]]), nil).should == '0'
    @db.bound_variable_arg(ActiveSupport::Duration.new(0, [[:seconds, -10.000001], [:minutes, -20], [:days, -3], [:months, -4], [:years, -6]]), nil).should == '-6 years -4 months -3 days -20 minutes -10.000001 seconds '
  end

  it "should support using ActiveSupport::Duration instances in array types in bound variables" do
    @db.bound_variable_arg([ActiveSupport::Duration.new(0, [[:seconds, 0]])].pg_array, nil).should == '{"0"}'
    @db.bound_variable_arg([ActiveSupport::Duration.new(0, [[:seconds, -10.000001], [:minutes, -20], [:days, -3], [:months, -4], [:years, -6]])].pg_array, nil).should == '{"-6 years -4 months -3 days -20 minutes -10.000001 seconds "}'
  end

  it "should parse interval type from the schema correctly" do
    @db.fetch = [{:name=>'id', :db_type=>'integer'}, {:name=>'i', :db_type=>'interval'}]
    @db.schema(:items).map{|e| e[1][:type]}.should == [:integer, :interval]
  end

  it "should support typecasting for the interval type" do
    ip = IPAddr.new('127.0.0.1')
    d = ActiveSupport::Duration.new(31557600 + 2*86400*30 + 3*86400*7 + 4*86400 + 5*3600 + 6*60 + 7, [[:years, 1], [:months, 2], [:days, 25], [:seconds, 18367]])
    @db.typecast_value(:interval, d).object_id.should == d.object_id

    @db.typecast_value(:interval, "1 year 2 mons 25 days 05:06:07").is_a?(ActiveSupport::Duration).should be_true
    @db.typecast_value(:interval, "1 year 2 mons 25 days 05:06:07").should == d
    @db.typecast_value(:interval, "1 year 2 mons 25 days 05:06:07").parts.sort_by{|k,v| k.to_s}.should == d.parts.sort_by{|k,v| k.to_s}
    @db.typecast_value(:interval, "1 year 2 mons 25 days 05:06:07.0").parts.sort_by{|k,v| k.to_s}.should == d.parts.sort_by{|k,v| k.to_s}

    @db.typecast_value(:interval, "1 year 2 mons 25 days 5 hours 6 mins 7 secs").is_a?(ActiveSupport::Duration).should be_true
    @db.typecast_value(:interval, "1 year 2 mons 25 days 5 hours 6 mins 7 secs").should == d
    @db.typecast_value(:interval, "1 year 2 mons 25 days 5 hours 6 mins 7 secs").parts.sort_by{|k,v| k.to_s}.should == d.parts.sort_by{|k,v| k.to_s}
    @db.typecast_value(:interval, "1 year 2 mons 25 days 5 hours 6 mins 7.0 secs").parts.sort_by{|k,v| k.to_s}.should == d.parts.sort_by{|k,v| k.to_s}

    d2 = ActiveSupport::Duration.new(1, [[:seconds, 1]])
    @db.typecast_value(:interval, 1).is_a?(ActiveSupport::Duration).should be_true
    @db.typecast_value(:interval, 1).should == d2
    @db.typecast_value(:interval, 1).parts.sort_by{|k,v| k.to_s}.should == d2.parts.sort_by{|k,v| k.to_s}

    proc{@db.typecast_value(:interval, 'foo')}.should raise_error(Sequel::InvalidValue)
    proc{@db.typecast_value(:interval, Object.new)}.should raise_error(Sequel::InvalidValue)
  end
end
end

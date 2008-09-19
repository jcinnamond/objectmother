# Define some dummy classes to use with ObjectMother
class User
  def self.create (*args); end
  def self.create! (*args); end
  def self.destroy (*args); end
end

class Rock < User
end

describe "ObjectMother" do
  before(:all) do
    # This makes sure that RAILS_ROOT is set even if this is not run from
    # inside a rails app.
    begin
      RAILS_ROOT
    rescue NameError
      Object.const_set(:RAILS_ROOT, File.dirname(__FILE__))
    end

    require File.join(File.dirname(__FILE__), '..', 'lib', 'object_mother')
    @prototypes_dir = File.join(File.dirname(__FILE__), 'prototypes')
  end

  describe "prototypes" do
    describe "directory" do
      it "should use paramaters" do
        dir = @prototypes_dir
        om = ObjectMother.new(dir)
        om.prototype_dir.should == dir
      end

      it "should use rspec if available" do
        dir = File.join(RAILS_ROOT, 'spec', 'object_mother')
        File.stub!(:exists?).with(dir).and_return(true)
        om = ObjectMother.new(dir)
        om.prototype_dir.should == dir
      end

      it "should use test if rspec is not available" do
        dir = File.join(RAILS_ROOT, 'test', 'object_mother')
        File.stub!(:exists?).with(dir).and_return(true)
        om = ObjectMother.new(dir)
        om.prototype_dir.should == dir
      end
    end

    it "should include the User module" do
      dir = File.join(File.dirname(__FILE__), 'prototypes')
      ObjectMother.new(dir)
      Object.constants.should include('User')
    end

    it "should cope with prototype directory being unset" do
      lambda do 
        ObjectMother.new
      end.should_not raise_error(Exception)
    end
  end

  describe "defining prototypes" do
    before(:each) do
      dir = File.join(File.dirname(__FILE__), 'prototypes')
      @object_mother = ObjectMother.new(dir)
    end

    it "should call define with the class name" do
      ObjectMother.should_receive(:define_prototype).with('user', [])
      ObjectMother.define_user
    end

    it "should pass in the remaining arguments to define" do
      args = [:betty, { :name => 'betty'}]
      ObjectMother.should_receive(:define_prototype).with('user', args)
      ObjectMother.define_user :betty, :name => 'betty'
    end

    it "should create a new method matching the first argument to define" do
      name = :betty
      ObjectMother.instance_methods.should_not include(name.to_s)
      ObjectMother.define_user name
      ObjectMother.instance_methods.should include(name.to_s)
    end
  end

  describe "defined methods with conditions" do
    before(:each) do
      @name = :wilma
      @args = { :name => 'wilma' }
      ObjectMother.define_user @name, @args
      @om = ObjectMother.new(@prototypes_dir)
    end

    it "should try to create" do
      User.should_receive(:create).with(@args)
      @om.send(@name)
    end

    it "should merge in the any arguments" do
      args = { :married_to => :fred }
      User.should_receive(:create).with(@args.merge(args))
      @om.send(@name, args)
    end

    it "should return the object" do
      user = User.new
      user.stub!(:id)
      User.stub!(:create).and_return(user)
      @om.send(@name).should == user
    end
  end

  describe "defined methods with procs" do
    before(:each) do
      # Add an id method to string so that it can be cached
      @id = 456
      String.module_eval("def id; #{@id}; end")

      @name = :barney
      ObjectMother.define(@name) { |a| a.upcase }
      @om = ObjectMother.new(@prototypes_dir)
    end

    it "should call the proc" do
      @om.send(@name, 'hello').should == "HELLO"
    end

    it "should cache the result if it has an ID" do
      @om.send(@name, 'hello')
      @om.cached_ids[@name].should == @id
    end
  end

  describe "caching an object" do
    before(:each) do
      @user = User.new
      @user.stub!(:id).and_return(123)
      User.stub!(:create).and_return(@user)

      @name = :wilma
      @args = { :name => 'wilma' }
      ObjectMother.define_user @name, @args
      @om = ObjectMother.new(@prototypes_dir)
    end

    it "should respond to cached ids" do
      @om.should respond_to(:cached_ids)
    end

    it "should have a hash of cached ids" do
      @om.cached_ids.should be_kind_of(Hash)
    end

    it "should cache the object ID against the name" do
      @om.send(@name)
      @om.cached_ids[@name].should == @user.id
    end

    it "should use the cached object ID to find the object" do
      @om.send(@name)
      @om.cached_ids[@name].should == @user.id

      User.should_receive(:find_by_id).with(@user.id)
      @om.send(@name)
    end
  end

  describe "chaining prototypes" do
    before(:each) do
      @om = ObjectMother.new(@prototypes_dir)
      @um = UserMother.new
      @um.should respond_to(:user_prototype)

      @name = 'fred'
      UserMother.define_user @name
    end

    it "should use the prototype" do
      User.should_receive(:create).with(@um.user_prototype)
      @um.send(@name)
    end

    it "should merge the prototype with other arguments" do
      name = 'dino'
      args = { :pet => true }
      UserMother.define_user(name, args)

      expected_args = @um.user_prototype.merge(args)
      User.should_receive(:create).with(expected_args)
      @um.send(name)
    end
  end

  describe "creating new objects based on prototypes" do
    before(:each) do
      @om = ObjectMother.new(@prototypes_dir)
      @um = UserMother.new
      @um.should respond_to(:user_prototype)
    end

    it "should create an object based on the prototype" do
      User.should_receive(:create).with(@um.user_prototype)
      @um.create_user
    end

    it "should cope if no prototype exists" do
      @um.should_not respond_to(:rock_prototype)
      Rock.should_receive(:create).with({})
      @um.create_rock
    end

    it "should merge hash args into the prototype" do
      args = { :pet => true, :barks => :like_a_dog }
      User.should_receive(:create).with(@um.user_prototype.merge(args))
      @um.create_user(args)
    end

    it "should return the object" do
      user = User.new
      User.stub!(:create).and_return(user)
      @um.create_user.should == user
    end

    it "should call a given block" do
      called = nil
      @um.create_user do |prototype|
        called = true
      end

      called.should be_true
    end

    it "should pass the prototype into a given block" do
      @um.create_user do |prototype|
        prototype.should == @um.user_prototype
      end
    end

    it "should merge hash args into the prototype before calling the block" do
      args = { :pet => true, :barks => :like_a_dog }
      @um.create_user(args) do |prototype|
        prototype.should == @um.user_prototype.merge(args)
      end
    end

    it "should return the result of a given block" do
      user = User.new
      obj = @um.create_user do
        user
      end
      obj.should == user
    end
  end

  describe "recreating defined objects" do
    before(:each) do
      @name = :yogi
      @args = { :name => 'yogi' }
      ObjectMother.define_user @name, @args
      @om = ObjectMother.new(@prototypes_dir)

      @id = 123
      @om.cached_ids[@name] = @id
    end

    it "should destroy cached objects" do
      User.should_receive(:destroy).with(@id)
      @om.send("recreate_#{@name}")
    end

    it "should not try to destroy uncached objects" do
      @om.cached_ids.delete(@name)
      User.should_not_receive(:destroy)
      @om.send("recreate_#{@name}")
    end

    it "should create a new object from the prototype" do
      User.should_receive(:create).with(@args).and_return(nil)
      @om.send("recreate_#{@name}")
    end

    it "should merge arguments into the prototype" do
      args = { :smarter_than_the_average_bear => true }
      User.should_receive(:create).with(@args.merge(args)).and_return(nil)
      @om.send("recreate_#{@name}", args)
    end
  end

  describe "calling create if an exclaimation mark is given" do
    before(:each) do
      @name = :bobo
      @om = ObjectMother.new(@prototypes_dir)
      ObjectMother.define_user(@name)
    end

    it "should work for defined methods" do
      User.should_receive(:create!)
      @om.send("#{@name}!")
    end

    it "should work when using the prototype" do
      um = UserMother.new
      um.should respond_to(:user_prototype)

      User.should_receive(:create!)
      um.send(:create_user!)
    end
  end
end


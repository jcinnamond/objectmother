class ObjectMother
  RSPEC_PROTOTYPE_DIR = File.join(RAILS_ROOT, 'spec', 'object_mother')
  TEST_PROTOTYPE_DIR = File.join(RAILS_ROOT, 'test', 'object_mother')

  # Everything is a class method
  class << self

    # ------------------------------------------------------------------------
    # Defining the directory containing the prototypes

    # Stores the directory to auto-include ObjectMother subclasses from.
    @@prototype_dir = nil
    def prototype_dir= (dir); set_prototype_dir(dir); end
    def prototype_dir; @@prototype_dir || set_prototype_dir; end

    # Sets the prototype directory to a given value or some default.
    def set_prototype_dir(dir = nil)
      previous_prototype_dir = @@prototype_dir
      @@prototype_dir = dir ||
        dir_exists(RSPEC_PROTOTYPE_DIR) ||
        dir_exists(TEST_PROTOTYPE_DIR)
      require_prototypes(@@prototype_dir) unless previous_prototype_dir == @@prototype_dir
      @@prototype_dir
    end

    # Returns the directory name if it exists.
    def dir_exists (dir)
      if File.exists?(dir) && File.stat(dir).directory?
        dir
      else
        nil
      end
    end

    # Requires any .rb files from a given directory.
    def require_prototypes(dir)
      return unless dir
      Dir.glob(File.join(dir, '**', '*.rb')).each do |file|
        require file
      end
    end


    # ------------------------------------------------------------------------
    # Caching object IDs. This is used to reload named prototypes from the
    # database, rather than recreating them. In turn, this helps avoid
    # problems with uniqueness constraints when reusing named prototypes
    # across tests.

    # Stores the IDs of named prototypes created by ObjectMother. 
    @@cached_ids = Hash.new
    def cached_ids; @@cached_ids; end

    # Loads a named prototype based upon its cached ID.
    def cache_fetch (name, class_name)
      klass = Object.const_get(classify(class_name))
      obj = nil
      if self.cached_ids.has_key?(name)
        obj = klass.send(:find_by_id, self.cached_ids[name])
      end
      obj
    end

    # Stores the ID of a named prototype in the cache.
    def cache (name, obj)
      if obj && obj.respond_to?(:id)
        self.cached_ids[name] = obj.id
      end
      obj
    end


    # ------------------------------------------------------------------------
    # Method missing magic.
    #
    # This picks up define_xxx or create_xxx methods and routes them
    # appropraitely.
    def method_missing (sym, *args, &block)
      matchdata = %r{^define_?(.*)}.match(sym.to_s)
      if matchdata
        define_prototype(matchdata[1], args, &block)
        return
      end

      matchdata = %r{^create_([^!]+)(!?)}.match(sym.to_s)
      if matchdata
        hashargs = args.first || {}
        return create_from_prototype(matchdata[1], hashargs, matchdata[2] == '!', &block)
      end

      super
    end


    # ------------------------------------------------------------------------
    # Defining prototypes

    # Creates methods matching a named prototypes. This allows you to user:
    #
    #   define_user :john, :name => 'John'
    #
    # to define a method called <tt>john</tt> that creates a new User object,
    # passing in <tt>{ :name => 'John' }</tt> to the create method.
    #
    # You can also specify a block which takes care of the creation of the
    # object, e.g.
    #
    #   define :john do
    #     User.create(:name => 'John', :employee_number => User.count + 1)
    #   end
    #
    # A corresponding ! method is also created. This behaves in the same way
    # except that it calls <tt>create!</tt> rather than <tt>create</tt> so
    # that exceptions are raised.
    #
    # Finally, a method called <tt>recreate_john</tt> is created to ensure
    # that any cached object is destroyed, and a new one created from the
    # prototype.
    def define_prototype (klass, args, &block)
      name = args.shift
      hashargs = args.shift

      if block_given?
        define_class_method(name) do |*block_args|
          obj = yield *block_args
          cache(name, obj)
        end
      else
        define_class_method(name) do |*block_args|
          create_args = hashargs || {}

          if block_args.first.kind_of?(Hash)
            create_args = hashargs.merge(block_args.first)
          end

          self.find_or_create(name, klass, create_args)
        end

        define_class_method("#{name}!") do |*block_args|
          create_args = hashargs || {}

          if block_args.first.kind_of?(Hash)
            create_args = hashargs.merge(block_args.first)
          end

          find_or_create(name, klass, create_args, true)
        end
      end

      define_class_method("recreate_#{name}") do |*block_args|
        recreate_args = hashargs

        if block_args.first.kind_of?(Hash)
          recreate_args = hashargs.merge(block_args.first)
        end
        recreate(name, klass, recreate_args)
      end
    end

    # ------------------------------------------------------------------------
    # Prototype creation.
    #
    # The following methods actually create objects from prototypes, or load
    # named objects from the cache.

    # This is the entry point for using named prototypes (i.e., those created
    # with 'define_xxx :name'). It first tries to load the object based on
    # a cached id (if available). Otherwise it uses create_from_prototype
    # to create a new object.
    #
    # All created named prototypes are added to the cache.
    def find_or_create (name, class_name, args, raise_exceptions = false)
      # Try the cache first
      obj = cache_fetch(name, class_name)

      # If there is not cache hit, create the object
      obj ||= create_from_prototype(class_name, args, raise_exceptions)

      cache(name, obj)
    end

    # This destroys and then recreates a named prototype. Use it when you
    # want to bypass the cache.
    def recreate (name, class_name, args)
      klass = Object.const_get(classify(class_name))
    
      id = cached_ids.delete(name)
      klass.send(:destroy, id) if id

      self.send(name, args)
    end

    # This creates objects based on their prototype. It merges together any
    # of the prototype definitions and sends them to create.
    def create_from_prototype (class_name, args = nil, raise_exceptions = false)
      klass = Object.const_get(classify(class_name))

      merged_args = Hash.new

      prototype_method = "#{class_name}_prototype"
      if self.respond_to?(prototype_method)
        merged_args = self.send(prototype_method)
      end

      if args.kind_of?(Hash)
        merged_args.merge!(args)
      end

      if block_given?
        yield merged_args
      else
        method = :create
        method = :create! if raise_exceptions
        klass.send(method, merged_args)
      end
    end

    # ------------------------------------------------------------------------
    # Helper methods

    def classify (word)
      word.gsub(/(^|_)(\w)/) do |s|
        if s == '_'
          ''
        else
          s.upcase
        end
      end
    end

    # Dynamically defines class methods. This is a little tricky.
    # See: http:blog.jayfields.com/2007/10/ruby-defining-class-methods.html
    def define_class_method (name, &block)
      (class << self; self; end).instance_eval do
        define_method(name, block)
      end
    end
  end
end

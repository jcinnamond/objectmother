class ObjectMother
  RSPEC_PROTOTYPE_DIR = File.join(RAILS_ROOT, 'spec', 'object_mother')
  TEST_PROTOTYPE_DIR = File.join(RAILS_ROOT, 'test', 'object_mother')

  attr_accessor :prototype_dir
  attr_accessor :cached_ids

  def initialize (dir = nil)
    self.prototype_dir = dir || set_prototype_dir
    require_prototypes

    self.cached_ids = Hash.new
  end

  def self.method_missing (sym, *args, &block)
    matchdata = %r{^define_?(.*)}.match(sym.to_s)
    if matchdata
      define_prototype(matchdata[1], args, &block)
      return
    end

    super
  end

  def self.define_prototype (klass, args, &block)
    name = args.shift
    hashargs = args.shift

    if block_given?
      define_method(name) do |*block_args|
        obj = yield *block_args
        cache(name, obj)
      end
    else
      define_method(name) do |*block_args|
        create_args = hashargs || {}

        if block_args.first.kind_of?(Hash)
          create_args = hashargs.merge(block_args.first)
        end

        find_or_create(name, klass, create_args)
      end

      define_method("#{name}!") do |*block_args|
        create_args = hashargs || {}

        if block_args.first.kind_of?(Hash)
          create_args = hashargs.merge(block_args.first)
        end

        find_or_create(name, klass, create_args, true)
      end
    end

    define_method("recreate_#{name}") do |*block_args|
      recreate_args = hashargs

      if block_args.first.kind_of?(Hash)
        recreate_args = hashargs.merge(block_args.first)
      end
      recreate(name, klass, recreate_args)
    end
  end

  def method_missing (sym, *args, &block)
    matchdata = %r{^create_([^!]+)(!?)}.match(sym.to_s)
    if matchdata
      hashargs = args.first || {}
      return create_from_prototype(matchdata[1], hashargs, matchdata[2] == '!', &block)
    end

    super
  end

  protected

  def require_prototypes
    return unless prototype_dir
    Dir.glob(File.join(prototype_dir, '**', '*.rb')).each do |file|
      require file
    end
  end

  def set_prototype_dir
    dir_exists(RSPEC_PROTOTYPE_DIR) || dir_exists(TEST_PROTOTYPE_DIR)
  end

  def dir_exists (dir)
    if File.exists?(dir) && File.stat(dir).directory?
      dir
    else
      nil
    end
  end

  def recreate (name, class_name, args)
    klass = Object.const_get(classify(class_name))
    
    id = cached_ids.delete(name)
    klass.send(:destroy, id) if id

    self.send(name, args)
  end

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

  def find_or_create (name, class_name, args, raise_exceptions = false)
    # Try the cache first
    obj = cache_fetch(name, class_name)

    # If there is not cache hit, create the object
    obj ||= create_from_prototype(class_name, args, raise_exceptions)

    cache(name, obj)
  end

  def cache_fetch (name, class_name)
    klass = Object.const_get(classify(class_name))
    obj = nil
    if self.cached_ids.has_key?(name)
      obj = klass.send(:find_by_id, self.cached_ids[name])
    end
    obj
  end

  def cache (name, obj)
    if obj && obj.respond_to?(:id)
      self.cached_ids[name] = obj.id
    end
    obj
  end

  def classify (word)
    word.gsub(/(^|_)(\w)/) do |s|
      if s == '_'
        ''
      else
        s.upcase
      end
    end
  end
end

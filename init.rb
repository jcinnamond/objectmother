if RAILS_ENV == "test"
  require File.join(File.dirname(__FILE__), 'lib', 'object_mother')
  # Force the loading of the prototype definitions
  ObjectMother.prototype_dir
end

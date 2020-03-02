module ActiveRecord
  # client side ActiveRecord::Base proxy
  class Base
    finder_method :__hyperstack_internal_scoped_first do
      first
    end

    scope :__hyperstack_internal_scoped_first_n, ->(n) { first(n) }

    def self.__hyperstack_internal_scoped_find_by(attrs)
      collection = all.apply_scope(:___hyperstack_internal_scoped_find_by, attrs)
      if !collection.collection
        collection._find_by_initializer(self, attrs)
      else
        collection[0]
      end
    end
  end unless Base.respond_to? :__hyperstack_internal_scoped_first_n
end

module ReactiveRecord
  class Collection

    def method_missing(method, *args, &block)
      if args.count == 1 && method.start_with?('find_by_')
        find_by(method.sub(/^find_by_/, '') => args[0])
      elsif [].respond_to? method
        all.send(method, *args, &block)
      elsif ScopeDescription.find(@target_klass, method)
        apply_scope(method, *args)
      elsif @target_klass.respond_to?(method) && ScopeDescription.find(@target_klass, "_#{method}")
        apply_scope("_#{method}", *args)[0]
      else
        super
      end
    end

    def first(n = nil)
      if n
        apply_scope(:__hyperstack_internal_scoped_first_n, n)
      else
        __hyperstack_internal_scoped_first
      end
    end
  end
end if RUBY_ENGINE == 'opal'

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  regulate_scope :all
end

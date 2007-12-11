require 'puppet/indirector'
require 'puppet/indirector/indirection'
require 'puppet/util/instance_loader'

# A simple class that can function as the base class for indirected types.
class Puppet::Indirector::Terminus
    require 'puppet/util/docs'
    extend Puppet::Util::Docs

    class << self
        include Puppet::Util::InstanceLoader

        attr_accessor :name, :terminus_type
        attr_reader :abstract_terminus, :indirection

        # Are we an abstract terminus type, rather than an instance with an
        # associated indirection?
        def abstract_terminus?
            abstract_terminus
        end

        # Convert a constant to a short name.
        def const2name(const)
            const.sub(/^[A-Z]/) { |i| i.downcase }.gsub(/[A-Z]/) { |i| "_" + i.downcase }.intern
        end

        # Look up the indirection if we were only provided a name.
        def indirection=(name)
            if name.is_a?(Puppet::Indirector::Indirection)
                @indirection = name
            elsif ind = Puppet::Indirector::Indirection.instance(name)
                @indirection = ind
            else
                raise ArgumentError, "Could not find indirection instance %s for %s" % [name, self.name]
            end
        end

        def indirection_name
            @indirection.name
        end

        # Register our subclass with the appropriate indirection.
        # This follows the convention that our terminus is named after the
        # indirection.
        def inherited(subclass)
            longname = subclass.to_s
            if longname =~ /#<Class/
                raise Puppet::DevError, "Terminus subclasses must have associated constants"
            end
            names = longname.split("::")

            # Convert everything to a lower-case symbol, converting camelcase to underscore word separation.
            name = names.pop.sub(/^[A-Z]/) { |i| i.downcase }.gsub(/[A-Z]/) { |i| "_" + i.downcase }.intern

            subclass.name = name

            # Short-circuit the abstract types, which are those that directly subclass
            # the Terminus class.
            if self == Puppet::Indirector::Terminus
                subclass.mark_as_abstract_terminus
                return
            end

            # Set the terminus type to be the name of the abstract terminus type.
            # Yay, class/instance confusion.
            subclass.terminus_type = self.name

            # Our subclass is specifically associated with an indirection.
            indirection_name = names.pop.sub(/^[A-Z]/) { |i| i.downcase }.gsub(/[A-Z]/) { |i| "_" + i.downcase }.intern

            if indirection_name == "" or indirection_name.nil?
                raise Puppet::DevError, "Could not discern indirection model from class constant"
            end

            # This will throw an exception if the indirection instance cannot be found.
            # Do this last, because it also registers the terminus type with the indirection,
            # which needs the above information.
            subclass.indirection = indirection_name

            # And add this instance to the instance hash.
            Puppet::Indirector::Terminus.register_terminus_class(subclass)
        end

        # Mark that this instance is abstract.
        def mark_as_abstract_terminus
            @abstract_terminus = true
        end

        def model
            indirection.model
        end

        # Convert a short name to a constant.
        def name2const(name)
            name.to_s.capitalize.sub(/_(.)/) { |i| $1.upcase }
        end

        # Register a class, probably autoloaded.
        def register_terminus_class(klass)
            setup_instance_loading klass.indirection_name
            instance_hash(klass.indirection_name)[klass.name] = klass
        end

        # Return a terminus by name, using the autoloader.
        def terminus_class(indirection_name, terminus_type)
            setup_instance_loading indirection_name
            loaded_instance(indirection_name, terminus_type)
        end

        # Return all terminus classes for a given indirection.
        def terminus_classes(indirection_name)
            setup_instance_loading indirection_name
            
            # Load them all.
            instance_loader(indirection_name).loadall

            # And return the list of names.
            loaded_instances(indirection_name)
        end

        private

        def setup_instance_loading(type)
            unless instance_loading?(type)
                instance_load type, "puppet/indirector/%s" % type
            end
        end
    end

    # Do we have an update for this object?  This compares the provided version
    # to our version, and returns true if our version is at least as high
    # as the asked-about version.
    def has_most_recent?(key, vers)
        raise Puppet::DevError.new("Cannot check update status when no 'version' method is defined") unless respond_to?(:version)

        if existing_version = version(key)
            #puts "%s fresh: %s (%s vs %s)" % [self.name, (existing_version.to_f >= vers.to_f).inspect, existing_version.to_f, vers.to_f]
            existing_version.to_f >= vers.to_f
        else
            false
        end
    end

    def indirection
        self.class.indirection
    end

    def initialize
        if self.class.abstract_terminus?
            raise Puppet::DevError, "Cannot create instances of abstract terminus types"
        end
    end
    
    def model
        self.class.model
    end
    
    def name
        self.class.name
    end
    
    def terminus_type
        self.class.terminus_type
    end

    # Provide a default method for retrieving an instance's version.
    # By default, just find the resource and get its version.  Individual
    # terminus types can override this method to provide custom definitions of
    # 'versions'.
    def version(name)
        raise Puppet::DevError.new("Cannot retrieve an instance's version without a :find method") unless respond_to?(:find)
        if instance = find(name)
            instance.version
        else
            nil
        end
    end
end

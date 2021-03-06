#
# The NXAPI provider for cisco_ace.
#
# July, 2015
#
# Copyright (c) 2015 Cisco and/or its affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'cisco_node_utils' if Puppet.features.cisco_node_utils?
begin
  require 'puppet_x/cisco/autogen'
rescue LoadError # seen on master, not on agent
  # See longstanding Puppet issues #4248, #7316, #14073, #14149, etc. Ugh.
  require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..',
                                     'puppet_x', 'cisco', 'autogen.rb'))
end

Puppet::Type.type(:cisco_ace).provide(:nxapi) do
  desc 'The NXAPI provider.'

  confine feature: :cisco_node_utils
  defaultfor operatingsystem: :nexus

  mk_resource_methods

  # Property symbol array for method auto-generation.
  #
  ACL_NON_BOOL_PROPS = [
    :action,
    :proto,
    :src_addr,
    :src_port,
    :dst_addr,
    :dst_port,
  ]

  ACL_BOOL_PROPS = [
  ]

  ACL_ALL_PROPS = ACL_NON_BOOL_PROPS + ACL_BOOL_PROPS

  PuppetX::Cisco::AutoGen.mk_puppet_methods(:non_bool, self, '@ace',
                                            ACL_NON_BOOL_PROPS)
  PuppetX::Cisco::AutoGen.mk_puppet_methods(:bool, self, '@ace',
                                            ACL_BOOL_PROPS)

  def initialize(value={})
    super(value)
    afi = @property_hash[:afi]
    acl_name = @property_hash[:acl_name]
    seqno    = @property_hash[:seqno]
    @ace = Cisco::Ace.aces[afi][acl_name][seqno] unless acl_name.nil? || seqno.nil?
    @property_flush = {}
  end

  def self.properties_get(afi, acl_name, seqno, instance)
    debug "Checking acl instance, #{afi} #{acl_name} #{seqno}"
    current_state = {
      name:     "#{afi} #{acl_name} #{seqno}",
      acl_name: acl_name,
      seqno:    seqno,
      ensure:   :present,
      afi:      afi,
    }

    # Call node_utils getter for each property
    ACL_NON_BOOL_PROPS.each do |prop|
      current_state[prop] = instance.send(prop)
    end
    ACL_BOOL_PROPS.each do |prop|
      val = instance.send(prop)
      if val.nil?
        current_state[prop] = nil
      else
        current_state[prop] = val ? :true : :false
      end
    end
    debug current_state
    new(current_state)
  end # self.properties_get

  def self.instances
    ace_hash = []
    Cisco::Ace.aces.each do |afi, acl_aces|
      acl_aces.each do |acl_name, aces|
        aces.each do |seqno, ace_instance|
          ace_hash << properties_get(afi, acl_name, seqno, ace_instance)
        end
      end
    end
    ace_hash
  end

  def self.prefetch(resources)
    ace_instances = instances
    resources.keys.each do |name|
      provider = ace_instances.find do |ace|
        resources[name][:afi] == ace.afi.to_s &&
        resources[name][:acl_name] == ace.acl_name.to_s &&
        resources[name][:seqno] == ace.seqno.to_i
      end
      resources[name].provider = provider unless provider.nil?
    end
  end # self.prefetch

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure] = :present
  end

  def destroy
    @property_flush[:ensure] = :absent
  end

  def properties_set(new_ace=false)
    ACL_ALL_PROPS.each do |prop|
      next unless @resource[prop]
      if new_ace
        # Set @property_flush for the current object
        send("#{prop}=", @resource[prop])
      end
      next if @property_flush[prop].nil?
      # Call the AutoGen setters for the @ace
      # node_utils object.
      @ace.send("#{prop}=", @property_flush[prop]) if
        @ace.respond_to?("#{prop}=")
    end
    # Set methods that are not autogenerated follow.
    ace_set
  end

  # Custom setters.
  # The following properties are setters and cannot be handled
  # by PuppetX::Cisco::AutoGen.mk_puppet_methods.
  def ace_set
    attrs = {}
    [:action, :proto, :src_addr, :src_port, :dst_addr, :dst_port].each do |p|
      attrs[p] = @property_flush[p] if @property_flush[p]
    end
    return if attrs.empty?
    @ace.ace_set(@property_flush)
  end

  def flush
    if @property_flush[:ensure] == :absent
      @ace.destroy
      @ace = nil
    else
      if @ace.nil?
        new_ace = true
        @ace = Cisco::Ace.new(@resource[:afi], @resource[:acl_name],
                              @resource[:seqno])
      end
      properties_set(new_ace)
      puts_config
    end
  end

  def puts_config
    if @ace.nil?
      info "ace=#{@resource[:seqno]} is absent."
      return
    end

    # Dump all current properties for this interface
    current = sprintf("\n%30s: %s", 'afi', @ace.afi)
    current.concat(sprintf("\n%30s: %s", 'acl_name', @ace.acl_name))
    current.concat(sprintf("\n%30s: %s", 'seqno', @ace.seqno))
    ACL_ALL_PROPS.each do |prop|
      current.concat(sprintf("\n%30s: %s", prop, @ace.send(prop)))
    end
    debug current
  end # puts_config
end

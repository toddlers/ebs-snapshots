#!/usr/bin/env ruby

require 'rubygems'
require 'fog'
require 'yaml'

class EbsSnapshots

  def self.parse(args)
    options =  {}
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{__FILE__} [options]"
      opts.separator ""
      opts.on("-c","--config CONFIG", "read the options from file") do |c|
        fp = YAML::load(File.open(c))
        options[:provider] = fp["provider"]
        options[:key] = fp["aws_access_key_id"]
        options[:secret] = fp["aws_secret_key"]
        options[:region] = fp["aws_region"]
        options[:volumes] = fp["volumes"]
      end
      opts.on_tail("-h","--help","show this message") do 
        puts opts
        exit
      end
    end
    begin
      opts.parse!(args)
      raise OptionParser::MissingArgument "no provider specified" if not options[:provider]
      raise OptionParser::MissingArgument "no aws access kye id" if not options[:key]
      raise OptionParser::MissingArgument "no aws secret key specified" if not options[:secret]
      raise OptionParser::MissingArgument "no aws region specified " if not options[:volumes]
      rescue SystemExit
        exit
      rescue Exception => e
        puts e
        exit
      end
      options
  end


  def self.connection(provider,region,key,secret)
    connection = Fog::Compute.new({
      :provider => provider,
      :region => region,
      :aws_access_key_id => key,
      :aws_secret_access_key => secret
      })
  end

  def self.snapshot(connection,volumes)
    volumes.each do |vid,prop|

    # Set up a time stamp for naming the snapshots
    time_stamp = Time.now.strftime("%Y-%m-%d:%H:%M")
    date = Time.now.strftime("%Y-%m-%d")

    # skip volume with no attachment. Each attached volume will have a server_id
    next if connection.volumes.get(vid).server_id.nil?

    # Create a new snapshot transaction. It needs a description and 
    # a volume id to snapshot

    snapshot = connection.snapshots.new
    snapshot.description = "#{prop[:host]}:#{prop[:type]}:#{time_stamp}"
    snapshot.volume_id = vid

    # Now actually take the snapshot
    snapshot.save

    # To tag the snapshot we need the  snapshot id
    #  So reload the snapshot ifno to get it
    snapshot.reload

    # To tag something you need a key, value and resource id of what you want to tag
    connection.tags.create(:resource_id => snapshot.id, :key => "SnapshotLifetime", :value => prop[:lifetime])
    connection.tags.create(:resource_id => snapshot.id, :key => "Snapshothost", :value => prop[:host])
    connection.tags.create(:resource_id => snapshot.id, :key => "SnapshotType", :value => prop[:type])
    connection.tags.create(:resource_id => snapshot.id, :key => "SnapshotPersistence", :value => 'delete')
    connection.tags.create(:resource_id => snapshot.id, :key => "Name", :value => "#{prop[:host]}:#{prop[:type]}:#{date}")
    end
  end

  def self.delete_snapshot(connection)

    # Grab the current timestamp for the age calculation
    time = Time.now

    # Filtering out the snapshots
    persistence_tags = connection.tags.all(:key => 'SnapshotPersistence', :value => 'delete')
    persistence_tags.each do |tag|
      snapshot = connection.snapshots.get(tag.resource_id)
      snapshot_tags = snapshot.tags
      puts "Checking snapshot #{snapshot.description}"
      lifetime = snapshot_tags['SnapshotLifetime'].to_i
      type = snapshot_tags['SnapshotType']

      # Calculating the age of the snapshot
      age = if type.eql?('daily')
              (time - snapshot.created_at)/(86400)
            elsif type.eql?('hourly')
              (time - snapshot.created_at)/(3600)
            end

    # Delete the snapshot if its too old. Deleting a snapshot requires the snapshot id
      if age.to_i > lifetime.to_i
        puts "deleteing snapshot " + snapshot.id.to_s
        connection.delete_snapshot(snapshot.id)
      end
    end
  end

  def self.run(args)
    opts = parse(args)
    provider = opts[:provider]
    key_id = opts[:key]
    secret = opts[:secret]
    region = opts[:region]
    time = Time.now

    # Make a connection to AWS
    connection = connection(provider,region,key_id,secret)
    puts "\nCreating snapshots #{time.to_s}"
    puts "Snapshot created Successfully" if snapshot(connection,opts[:volumes])
    puts "Deleted old snapshots" if delete_snapshot(connection)
  end
end
EbsSnapshots.run(ARGV)

#!/usr/bin/env ruby

# gem install fog  --no-ri --no-rdoc
require 'rubygems' if RUBY_VERSION < "1.9"
require 'fog'
require 'yaml'
require 'optparse'

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
      opts.on("--dry","do a dry run and dont do anything") do
        options[:dry] = true
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

  def self.snapshot(connection,volumes,dry)
    if dry
      puts "\nBelow are the volumes id for snapshots"
      puts "\t" + volumes.keys.join(",")
    else
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
  end

  def self.delete_snapshot(connection,dry)

    # Grab the current timestamp for the age calculation
    time = Time.now

    # Filtering out the snapshots
    persistence_tags = connection.tags.all(:key => 'SnapshotPersistence', :value => 'delete')

    #connection.tags.all would give something lik this

    #<Fog::Compute::AWS::Tag
    #key="SnapshotPersistence",
    #value="delete",
    #resource_id="snap-1f5cdc9d",
    #resource_type="snapshot"
    #>

    snapshots_to_delete = []
    persistence_tags.each do |tag|

      #[13] pry(main)> conn.snapshots.get('snap-c8b0754a')
      #<Fog::Compute::AWS::Snapshot
      #id="snap-c8b0754a",
      #description="ec2-12-34-56-78.compute-1.amazonaws.com:daily:2015-03-12:00:00",
      #progress="100%",
      #created_at=2015-03-12 06:59:06 UTC,
      #owner_id="12324556",
      #state="completed",
      #tags={"Snapshothost"=>"ec2-12-34-56-78.compute-1.amazonaws.com", "ClusterType"=>"foo",
      #"SnapshotLifetime"=>"5d", "SnapshotType"=>"daily", "SnapshotPersistence"=>"delete",
      #"Name"=>"ec2-54-234-91-134.compute-1.amazonaws.com:daily:2015-03-12"},
      #volume_id="vol-838aa79a",
      #volume_size=200

      snapshot = connection.snapshots.get(tag.resource_id)
      snapshot_tags = snapshot.tags
      puts "\n\tChecking snapshot #{snapshot.description}"

      # checking for ami attached snapshots
      # delete call return something like this error
      # The snapshot snap-1e8ee39e is currently in use by ami-84dasdas

      next if "#{snapshot.description}"[ami]

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
        snapshots_to_delete << snapshot.id
      end
    end
    if not dry
      if not snapshots_to_delete.empty?
        puts "\ndeleting snapshots " + snapshots_to_delete.join(",")
        snapshots_to_delete.each do |s|
          connection.delete_snapshot(s)
        end
      else
        puts "\nNothing to delete"
      end
    else
      if not snapshots_to_delete.empty?
        puts "\nSnapshots for deletion " + snapshots_to_delete.join(",")
      else
        puts "\nNothing to delete"
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
    puts "Snapshot created Successfully" if snapshot(connection,opts[:volumes],opts[:dry])
    puts "Deleted old snapshots" if delete_snapshot(connection,opts[:dry])
  end
end
EbsSnapshots.run(ARGV)

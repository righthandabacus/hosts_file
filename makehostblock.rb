#!/usr/bin/env ruby
=begin
    Make a /etc/hosts file from various sources to block ad sites
    Wed, 07 Oct 2015 10:21:40 -0400
=end

require 'net/http'
require 'set'
require 'optparse'

# Predefined constants
SOURCE = [
	'http://winhelp2002.mvps.org/hosts.txt',
	'http://someonewhocares.org/hosts/hosts',
	'http://hosts-file.net/download/hosts.txt',
    'http://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext'
]
GOODHOSTS = ['localhost','broadcasthost','localdomain','local'].to_set
LOOPBACK = ['0.0.0.0','::1','127.0.0.1','255.255.255.255'].to_set
HOSTREGEX = /^\s*([:\.\h]+)\s+([^\s#]+)/

# Define class for output host file
class HostFile
    attr_writer :allow_all

    def initialize(sort, clean)
        @sort = sort
        @clean = sort or clean # sort implies clean
        @knownhosts = Set.new
        @outfile = []
        @allow_all = false # allow non-loopback entries
    end

    def add_host(domain_name)
        # add domain name to set, return boolean to indicate if it is new
        return !(@knownhosts.add?(domain_name).nil?)
    end

    def add_lines(ln, force=false)
        # add lines to host file, but skip if not force and @clean is set
        if force or not @clean then
            if ln.instance_of? String then
                @outfile << ln
            elsif ln.instance_of? Array then
                @outfile.push(*ln)
            else
                raise('Adding to hosts file of not a string or array')
            end
        end
    end

    def <<(ln)
        if not ln.instance_of? String then
            raise('Adding to hosts file of not a string')
        else
            if captures = ln.match(HOSTREGEX) then
                if not @allow_all and not LOOPBACK.include?(captures[1]) then
                    raise("Non-loopback defintion #{ln}")
                elsif GOODHOSTS.include?(captures[2]) then
                    return self # skip this line as it should already be included in /etc/hosts header
                elsif not add_host(captures[2]) then
                    return self # skip this line due to duplicate
                end
            end
            @outfile << ln if not @clean
        end
        return self
    end

    def get_file
        # return host file as array of strings
        if not @sort then
            return @outfile
        else
            return @outfile.concat(['','# [makehostblock.rb] sorted',''])
                           .concat(@knownhosts.to_a.map{ |n| n.split('.').reverse }.sort.map{ |n| '0.0.0.0 '+n.reverse.join('.') })
        end
    end
end

# Parse command line options: controlling output format
options = {:out => nil, :sort => false, :clean => false}
OptionParser.new do |opts|
    opts.banner = 'makehostblock.rb [options]'
    opts.version = '0.1'
    opts.on('-oFILE','File to output, stdout if omitted') { |f| options[:out] = f }
    opts.on('-s','Sort output, implies -c') { |n| options[:sort] = true }
    opts.on('-c','Clean output by removing comments') { |n| options[:clean] = true }
end.parse!

hostfile = HostFile.new(options[:sort], options[:clean])

# Read in /etc/hosts 
oldhosts = File.readlines('/etc/hosts') or die
oldhosts_start = Range.new(0,oldhosts.length-1).select do |i|
	if captures = oldhosts[i].match(HOSTREGEX) then
        # Keep all those localhost definitions in /etc/hosts or those not pointing to loopback or IPv6 addresses
        next(true) if GOODHOSTS.include?(captures[2]) or not LOOPBACK.include?(captures[1]) or captures[1].include?(':')
    end
    next(false)
end.max

# Construct new /etc/hosts file
# Step 1: Keep useful definitions from /etc/hosts
hostfile.add_lines(oldhosts[0..oldhosts_start], true)

# Step 2: Gather ad site definitions from web and append (with duplicates removed)
SOURCE.each do |url|
    hostfile.add_lines(['','# [makehostblock.rb] '+url,''])
    Net::HTTP.get(URI(url)).split(/\r?\n/).each{ |ln| hostfile << ln }
end

# Step 3: [optional] Read from *.txt from local dir, with comment lines removed
Dir.glob('*.txt') do |filename|
    hostfile.add_lines(['','# [makehostblock.rb] '+filename,''])
    hostfile.allow_all = true
    File.readlines(filename).each do |ln|
        hostfile << ln
    end
end

# Step 4: Formatting output
if options[:out] then
    File.open(options[:out], 'w') { |file|
        file.puts hostfile.get_file
    }
else
    puts hostfile.get_file
end

__END__

vim:set ts=4 sw=4 sts=4 et:

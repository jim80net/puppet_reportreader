#!/usr/bin/ruby
# reportreader.rb
# Use to parse puppet reports. 
# Sample usage: 
# reportreader.rb -s all -t 24 -c 
# -to print out all changes in the last 24 hours.
# 
# Written by jim80net

def do_nothing() 
end # close do_nothing

################
#    INPUTS    #
require 'optparse'

# This hash will hold all of the options
# parsed from the command-line by OptionParser.
options = {}
optparse = OptionParser.new { |opts|
	# Set a banner, displayed at the top
	# of the help screen.
	opts.banner = "Usage: #{$0} [options]"

	# Define the options, and what they do

	options[:hours] = nil
	opts.on( '-t', '--time PARAM', 'Time scope by hours from now: default is 12') { |timeParam|
		options[:hours] = timeParam.to_f
	} # end opts.on

	options[:hostname] = nil
	opts.on( '-s', '--hostname PARAM', 'Identify hostname to check') { |hNameParam|
		options[:hostname] = hNameParam
	} # end opts.on
 
	options[:changes] = nil
	opts.on( '-c', '--changes', 'Print changed resources') { 
		options[:changes] = true
	} # end opts.on

	options[:logs] = nil
	opts.on( '-l', '--logs', 'Print logs from changed resources') { 
		options[:logs] = true
	} # end opts.on

	options[:verbose] = nil
	opts.on( '-v', '--verbose', 'Increase verbosity') { 
		options[:verbose] = true
	} # end opts.on

	options[:reportDir] = nil
	opts.on( '-f', '--reportdir PARAM', 'Identify reports directory (default: /var/lib/puppet/reports)') { |reportDirParam|
		options[:reportDir] = reportDirParam
	} # end opts.on

	# This displays the help screen, all programs are
	# assumed to have this option.
	opts.on( '-h', '--help', 'Display this screen' ) do
		puts opts
		exit
	end # end opts.on

} # optparse = OptionParser.new { |opts|

# Parse the command-line. Remember there are two forms
# of the parse method. The 'parse' method simply parses
# ARGV, while the 'parse!' method parses ARGV and removes
# any options found there.
optparse.parse!

#    INPUTS    #
################


#########################
#    PRE PROCESSING     #

# Recurse through reportDir in search of files. 
# Return files = file list
def process_files( aDir )
	require 'find'

	unless FileTest.directory?(aDir)
		puts "Error. Invalid input for report directory: #{aDir}."
		exit
	end # unless

	@@files = []
	@@directories = []
	Find.find( aDir ) { |f|
			@@files.push(f) if f.match(/\.yaml\Z/)
			if FileTest.directory?(f)
				 arr = f.split('/')
				 arr2 = arr[arr.length - 1]
				 @@directories.push(arr2) 
			end
	} # Find.find( aDir ) { |f|

	directories = @@directories[1..@@directories.length].sort
	return @@files,directories
end # def process_files( aDir )

def read_reports( fileList , hours=12)
	arr = []
	fileList.each { |f|
		
		if (Time.now - (hours*60*60)).gmtime.strftime("%Y%m%d%H%M") <  f[/[0-9]{12}.yaml/]
			File.open(f) { |g|
				if b = YAML.load(g) then
					hsh = {
						:filename => f,
						:configuration_version => b.configuration_version,
						:host => b.host,
						:kind => b.kind,
						:logs => b.logs,
						:metrics => b.metrics,
						:resource_statuses => b.resource_statuses,
						:status => b.status,
						:time => b.time,

						# :raw => b, # <-- This makes for some fairly large memory usage
					}
					arr.push(hsh)
				end # if b = 
			} # File.open
		end # if Time.now

	#	} # Thread.new
	} # fileList.each

	return arr

end # def read_reports( fileList )

#    PRE PROCESSING     #
#########################
	

#################
#    OUTPUTS    #

def extract_resource_statuses( resObj )
	aResource=[]
	resObj.each { |v| aResource.push(v)  }
	# aResource[n] {|v| [0] = name ; [1] = Puppet::Resource::Status }
	# http://rubydoc.info/github/puppetlabs/puppet/master/Puppet/Resource/Status
	@@string = ""
	aResource.each { |v| 
		if (v[1].change_count > 0 and v[1].resource != "Notify[environment_notice]") or (v[1].failed)
			@@string << %Q[\n\t#{v[0]} ]

			# Not included attributes: 
			# title
			# resource_type
			# change_count
			# out_of_sync_count
			# changed
			%W[
				resource
				failed
				events
	
				time
				evaluation_time
				file
				line
	
				status
				current_values
				default_log_level
				node
				source_description
	
				skipped

			].each { |x|
				@@string << %Q[\n\t\t#{x}: #{v[1].send( x.to_sym) }] if v[1].send( x.to_sym)
			}
		end # if v[1].change_count > 0
	} # aResource.each
	return @@string
end # def extract_resource_statuses( resObj )

def print_host_changes( anArr )
# http://rubydoc.info/github/puppetlabs/puppet/master/Puppet/Transaction/Report
	ob = anArr.sort_by { |v| v[:time] }
	ob2 = ob.sort_by {|v| v[:host] }
	ob2.each {|v| 
		string = extract_resource_statuses(v[:resource_statuses]) if v[:resource_statuses]
		puts(
			%Q[\nReport(#{v[:report_format].to_s}): #{v[:host]}  #{v[:time]} Config:#{v[:configuration_version]}  #{v[:status]}  #{string} ]
		) if (v[:status] == "changed" and  string != "") or (v[:status] == "failed")
	} ##{v[:kind]} #{v[:logs]}
end # def print_host_changes( aHostname, anArr ) 


def print_host_logs( anArr )
# http://rubydoc.info/github/puppetlabs/puppet/master/Puppet/Transaction/Report
	ob = anArr.sort_by { |v| v[:time] }
	ob2 = ob.sort_by {|v| v[:host] }
	ob2.each {|v| 
		if v[:status] == "changed"
			puts(%Q[\nReport: #{v[:host]}  #{v[:time]}  #{v[:status]} ] )
			puts(%Q[\t#{v[:logs]}])
		end
	}
end # def print_host_logs( anArr ) 

#    OUTPUTS    #
#################


##########################
#    MAIN (in effect)    #

# Set reportDir if not defined 
if options[:reportDir] 
	reportDir = options[:reportDir]
	if reportDir[reportDir.length] != "/"
		reportDir << "/"
	end
else
	reportDir = "/var/lib/puppet/reports/" 
end

# Set verbose if interactive
options[:verbose] = true if (options[:hostname] == nil or (options[:logs] == nil and options[:changes] == nil))


begin # main rescue block
	require 'yaml'
	require 'puppet'


	print("Loading filelist from " + reportDir.to_s() + ":...") if options[:verbose]
	findOutput=process_files(reportDir) 
	fileList=findOutput[0]
	dirList=findOutput[1]
	puts("Found #{fileList.count} files.") if options[:verbose]


	begin # options:hostname rescue block
		if options[:hostname] == nil
			puts(%Q[Found the following host entries:\n])
			dirList.sort.each {|v|
				puts("\t #{dirList.index(v)}: #{v}")
			} 
			print("done.\n\n") 
			print("Which host(s) do you want?['all' for all]:")
			ans = gets().chomp()
			# TODO: entering a string that is not dirList.include? will return array[0], as to_f for a string = 0.0
		else
			ans = options[:hostname]
		end # if options[:hostname] == nil

		if ans == "all"
			checkedList = fileList
		elsif dirList.include?(ans)
			checkedList = process_files(reportDir + ans)[0]
		elsif dirList.include?(dirList.values_at(ans.to_f).to_s) and !(ans == "") 
			checkedList = process_files(reportDir + dirList.values_at(ans.to_f).to_s)[0]
		else
			raise "Invalid hostname selection"
		end

		rescue RuntimeError => e
			puts e
			retry
	end # options:hostname rescue block


	print("Reading reports:...")  if options[:verbose]
		a = read_reports(checkedList) if options[:hours] == nil # and options[:verbose] == nil
		a = read_reports(checkedList, options[:hours]) if options[:hours] # and options[:verbose] == nil
	print("done. Loaded #{a.length} records.\n") if options[:verbose]

	
	begin # options:changes rescue block
		if !(options[:changes] or options[:logs])
			puts("What information do you want?")
			print("\n c: Print host changes.")
			print("\n l: Print host logs.")
			print("\n q: exit from this menu.\n")
			print("Enter your selection:")
			ans = gets().chomp()
			case ans
				when /c/
					print_host_changes(a)
					raise "Returning to menu"
				when /l/
					print_host_logs(a)
					raise "Returning to menu"
				when /q/
					do_nothing
			    else
					raise "Invalid selection"
			end # case ans
		else
			print_host_changes(a) if options[:changes]
			print_host_logs(a) if options[:logs]
		end # if !(options[:changes] or options[:logs])

		rescue RuntimeError => e
			puts e
			retry
	end # options:changes rescue block


#	# Break out into interactive session
#	# http://bogojoker.com/readline/
#	require 'readline'
#	puts("Summary information is hashed into: a, an array")
#	puts("\n\nNo more code after this. Going interactive.")
#	puts("Newline to eval.'q' to exit.") 
#	program = ""
#	input = ""
#	line = ""
#	until line.strip() == "q"
#		line = Readline.readline('> ', true)
#		begin # rescue block
#		case( line.strip() )
#			when '' 
#				puts( "Evaluating..." )
#				eval( input ) 
#				input = ""
#			else 
#				input += line
#		end #case
#		rescue StandardError, SyntaxError => e
#			puts("Error: " + e.to_s)
#			input = ""
#			retry
#		end # rescue block
#	end # until
#
#	rescue RuntimeError => e
#		puts("Error: " + e.to_s)
#		retry


	# Rescue stuff
	rescue SystemExit, Interrupt
		puts("\nQuitting.\n")
		exit
	rescue StandardError => e
		puts("Error class: " + e.class.to_s)
		puts("Error: " + e.to_s )
		puts("Error backtrace: " + e.backtrace.to_s)
end # end main rescue block


#    MAIN (in effect)    #
##########################

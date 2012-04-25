#!/usr/bin/ruby
##
# :title: reportreader.rb
# :main: README.rdoc
# Use to parse puppet reports. 
# Sample usage: 
# reportreader.rb -s all -t 24 -c 
# -to print out all changes in the last 24 hours.
# 
# Written by jim80net

##
# Literally, do nothing. 

def do_nothing() 
end # close do_nothing

## --------------------------------------------------------------------
# :section: Pre-Processing
# ---------------------------------------------------------------------

##
# Recurse through aDir for yaml files, unless it is "zz_archive". 
# Return: [ [filelist], [[directory,last report in directory]] ]

def process_files( aDir )
	unless FileTest.directory?(aDir)
		puts "Error. Invalid input for report directory: #{aDir}."
		exit
	end # unless

	@@files = []
	@@directories = []

	##
	# The actual bit that does the recursing through the dir tree

	def process_files_recurse(aDir) 
		@@tempFiles = []

		Dir.foreach( aDir ) { |f|
			myPath = "#{aDir}\/#{f}"
			if FileTest.directory?(myPath) and f != '.' and f != '..' and f != 'zz_archive'
				 process_files_recurse(myPath)
			else
				@@tempFiles.push(myPath) if f.match(/\.yaml\Z/)
			end
		} # Find.find( aDir ) { |f|

		sortedTempFiles = @@tempFiles.sort 
		
		@@files.push(sortedTempFiles)
		@@directories.push([aDir[/[^\/]+$/],sortedTempFiles[sortedTempFiles.length - 1]])

	end # def process_files_recurse (aDir) 

	process_files_recurse(aDir)

	files = @@files.sort.flatten
	directories = @@directories[0..(@@directories.length - 2)].sort_by { |e| e.nil? ? 'z' : e[0] } 

	return files,directories

end # def process_files( aDir )

##
# Given array of filenames (fileList), and float of hours,
# Return: [ [files within timescope], [files outside of timescope] ]

def filter_by_time( fileList, hours=12 )
	arr = []
	olderarr = []

	fileList.each { |f|
		if (Time.now - (hours*60*60)).gmtime.strftime("%Y%m%d%H%M") <  f[/[0-9]{12}.yaml/]
			arr.push(f)
		else 
			olderarr.push(f)
		end # if (Time.now - (hours*60*60)).gmtime.strftime("%Y%m%d%H%M") <  f[/[0-9]{12}.yaml/]
	} #fileList.each { |f|

	arr2 = arr.sort { |x,y| y <=> x } # reverse sort puts present on top of past, though this means hostnames are backwards as well. 

	return arr2,olderarr

end # def filter_by_time( fileList, hours=12 )


##
# Given an array of files (fileList),
# Return {report attributes => value}

def read_report( fileList )
	File.open(fileList) { |g|
		if b = YAML.load(g) then
				strings = %W[host time logs metrics resource_statuses configuration_version
					report_format puppet_version kind status pending_count complaint_count
					failed_count]
				@@hsh = {}

				strings.each { |string|
					begin # strings.each rescue block
					@@hsh[string.to_sym] =  b.send(string.to_sym) 

					rescue NoMethodError # basically, do_nothing.
					end # strings.each rescue block
				} # strings.each { |string|

		end # if b = YAML.load(g) then

	} # File.open(f) { |g|

	return @@hsh

end # def read_report( fileList )


##
# Puppet::Resource::Status is the output from a 
# <tt> Puppet::Transaction::Report.resource_statuses[1]. </tt> 
# For each resource, 
# - compare tags against tagFilter and tagReverseFilter
# - eval against $customMethods
# Return @@string of resource attributes if above queries are true.
#
# http://rubydoc.info/github/puppetlabs/puppet/master/Puppet/Resource/Status 
#
# http://projects.puppetlabs.com/projects/puppet/wiki/Report_Format_3

def extract_resource_statuses( resObj, tagFilter=nil, tagReverseFilter=nil )

	@@string = ""

	resObj.each { |v| 
		@@skip = false

		if $customMethods != []
			@@skip = true

			$customMethods.each { |method|
				if method[1]
					@@skip = false if eval("v[1].#{method[0]} #{method[1]}")
				else
					@@skip = false if v[1].send(method[0]) 
				end # if method[1]

			} # $customMethods.each { |method|

		end # if $customMethods != []

		##
		# Not included attributes: 
		# title
		# resource_type
		 
		if $verbose
			resources = %W[
				resource
				failed
				changed
	
				time
				evaluation_time
				file
				line
	
				status
				current_values
				default_log_level
				node
				source_description
				change_count
				out_of_sync_count
				pending_count
				compliant_count
				failed_count
	
				skipped
				events
			]
		else 
			resources = %W[
				resource
				failed
				skipped
				events
			]
		end # if $verbose

		@@tagString = ""

		if tagFilter 
			@@tagMatch = false

			v[1].tags.each { |tag| 
				if Regexp.new(tagFilter).match(tag)
					@@tagMatch = true
					@@tagString << "\n\t\t\t#{tag}"
				end # if Regexp.new(tagFilter).match(tag)

			} # v[1].tags.each { |tag| 

		elsif tagReverseFilter
			@@tagMatch = true

			v[1].tags.each { |tag| 
				if Regexp.new(tagReverseFilter).match(tag)
					@@tagMatch = false
				end # unless Regexp.new(tagReverseFilter).match(tag)

			} # v[1].tags

		else
			@@tagMatch  = true # if neither are defined, print it
		end # if tagFilter
			
		@@resourceString = ""
		if @@tagMatch
			resources.each { |x|
				begin
					@@resourceString << %Q[\n\t\t#{x}: #{v[1].send( x.to_sym) }] if v[1].send( x.to_sym) 
				rescue NoMethodError # basically, do nothing
				end
			} # resources.each { |x|
		end # if @@tagMatch

		if @@resourceString != "" and @@skip == false
			@@string << %Q[\n\t#{v[0]} ] 
			@@string << @@resourceString
			@@string << "\n\t\tMatching tags: #{@@tagString.to_s}" if $verbose
		end # if @@resourceString != "" and @@skip == false

	} # aResource.each

	return @@string 

end # def extract_resource_statuses( resObj )

##
# Simpler extract method which, given Puppet::Transaction::Report.logs
# output, returns strings if within a certain log level
#--
# TODO: Tie this in as an addon to Resource reporting
#++ 
#
# http://projects.puppetlabs.com/projects/puppet/wiki/Report_Format_3

def extract_logs(logs)
	@@string = ""

	logs.each { |v|
		case v.level
			when (:info or :notice or :warning or :err or :alert or :emerg or :crit)
				@@string << "\n\t" + v.time.to_s + ": " + v.message 
			else # /:debug/ or /:info/ 
				do_nothing
		end #case v.level

	} # logs.each { |v|

	return @@string

end # def extract_logs(logs)
	

## --------------------------------------------------------------------
# :section: Outputs
# ---------------------------------------------------------------------

##
# Given filelist, read reports, then print matching reports and
# resources to STDOUT
#
# http://rubydoc.info/github/puppetlabs/puppet/master/Puppet/Transaction/Report

def print_host_changes( anArr, tagFilter=nil, tagReverseFilter=nil)
	anArr.each {|w| 
		v = read_report(w) 
		string = extract_resource_statuses(v[:resource_statuses], tagFilter, tagReverseFilter) if v[:resource_statuses]

		puts(
			%Q[\nReport(#{v[:report_format].to_s}): #{v[:host]}  #{v[:time]} Config:#{v[:configuration_version]}  #{v[:status]}  #{string} ]
		) if ( string and string.length() > 0 )

	} # anArr.each {|w| 

end # def print_host_changes( aHostname, anArr ) 

##
# Given filelist, read reports, then print matching logs and 
# resources to STDOUT

def print_host_logs( anArr, tagFilter=nil, tagReverseFilter=nil )
	anArr.each {|w| 
		v = read_report(w)
		string = extract_logs(v[:logs]) if v[:logs]

		puts(
			%Q[\nReport(#{v[:report_format].to_s}): #{v[:host]}  #{v[:time]} Config:#{v[:configuration_version]}  #{v[:status]}  #{string} ]
		) if ( string and string.length() > 0 ) #or (v[:status] == "failed")

	} # anArr.each {|w| 

end # def print_host_logs( anArr ) 

## --------------------------------------------------------------------
# :section: Main
# ---------------------------------------------------------------------


	##
	# :stopdoc:
	##

	## ----------------------------------------------------------------
	# :section: Options
	# -----------------------------------------------------------------

	require 'optparse'
	
	# This hash will hold all of the options
	# parsed from the command-line by OptionParser.
	options = {}

	# Create new OptionParser class to parse cmd line options
	optparse = OptionParser.new { |opts|

		# Set a banner, displayed at the top of the help screen.
		opts.banner = "Usage: #{$0} [options]"
	
		##
		# Define the options, and what they do
	
		options[:reportDir] = nil
		opts.on( '-f', '--reportdir PARAM', 'Identify reports directory (default: /var/lib/puppet/reports)') { |reportDirParam|
			options[:reportDir] = reportDirParam
		} # end opts.on
	
		options[:hours] = nil
		opts.on( '-t', '--time PARAM', 'Time scope by hours from now') { |timeParam|
			options[:hours] = timeParam.to_f
		} # end opts.on
	
		options[:deleteolder] = nil
		opts.on( '-D', '--deleteolder', 'Delete files older than "-t" time') { 
			options[:deleteolder] = true
		} # end opts.on
	
		options[:hostname] = nil
		opts.on( '-s', '--hostname PARAM', 'Identify hostname to check') { |hNameParam|
			options[:hostname] = hNameParam
		} # end opts.on
	
		options[:tagFilter] = nil
		opts.on( '-T', '--tags PARAM', "Identify tags to filter by. Verbose output includes matched tags. Wrap in single parens. Pretend the parens are the equivalent of / /. For example, \'[a-z]{6}\' matches tags > 5 alpha characters.") { |tagParam|
			options[:tagFilter] = tagParam
		} # end opts.on
	
		options[:tagReverseFilter] = nil
		opts.on( '-X', '--reverse-tags PARAM', 'Identify tags to filter by. Matches are excluded.') { |tagParam|
			options[:tagReverseFilter] = tagParam
		} # end opts.on
		

		##
		# :startdoc:
		##

		##
		# Given customMethods argument, return array of arrays:
		# <tt> [ [method_name, method_arguments] ] </tt>

		def parse_custom_methods(cMParam) 
			@arr = cMParam.split(',')

			@arr.each { |method|
				@meth = []

				if /\s/.match(method)
					@meth[0] = $`
					@meth[1] = $'
				else 
					@meth[0] = method
				end # if /\s/.match(method)

				$customMethods.delete(@meth)
				$customMethods.push(@meth)

			} # @arr.each { |method|

		end # def parse_custom_methods 

		##
		# :stopdoc:
		##

		$customMethods = []
		options[:customMethods] = nil
		opts.on( '-R', '--custom-method PARAM', 'send custom method to filter Puppet::Resource::Status. ex: -R "change_count > 0,failed" is equivalent to "-c".') { |cMParam|
			options[:customMethods] = true
			parse_custom_methods(cMParam)
		} # end opts.on

		options[:changes] = nil
		opts.on( '-c', '--changes', 'Print changed resources') { 
			options[:changes] = true
			parse_custom_methods('change_count > 0,failed')
		} # end opts.on
	
		options[:logs] = nil
		opts.on( '-l', '--logs', 'Print logs from changed resources') { 
			options[:logs] = true
		} # end opts.on
	
		options[:verbose] = nil
		opts.on( '-v', '--verbose', 'Increase verbosity') { 
			options[:verbose] = true
		} # end opts.on
	
		options[:breakout] = nil
		opts.on('--breakout', 'Breakout into interactive mode after main completes') {
			options[:breakout] = true
		} # end opts.on
	
		##
		# This displays the help screen, all programs are
		# assumed to have this option.

		opts.on( '-h', '--help', 'Display this screen' ) do
			puts opts
			exit
		end # end opts.on
	
	} # optparse = OptionParser.new { |opts|
	
	##
	# Parse the command-line. Remember there are two forms
	# of the parse method. The 'parse' method simply parses
	# ARGV, while the 'parse!' method parses ARGV and removes
	# any options found there.

	optparse.parse!
	

##
# Set reportDir if not defined 

if options[:reportDir] 
	reportDir = options[:reportDir]

	if reportDir[reportDir.length] != "/"
		reportDir << "/"
	end

else
	reportDir = "/var/lib/puppet/reports/" 
end

##
# Set verbose if interactive

options[:verbose] = true if (options[:hostname] == nil or (options[:logs] == nil and options[:changes] == nil))
$verbose = options[:verbose] # <-- I want this available globally

##
# main rescue block

begin 
	require 'yaml'
	require 'puppet'

	print("Loading filelist from " + reportDir.to_s() + ":...") if options[:verbose]
	findOutput=process_files(reportDir) 
	fileList=findOutput[0]
	dirList=findOutput[1]
	puts("Found #{fileList.count} files.") if options[:verbose]

	##
	# options[:hostname] rescue block

	begin 
		if options[:hostname] == nil
			puts(%Q[Found the following host entries:\n])
			puts(%Q[ Index: Hostname:                        Last Report: \n])

			dirList.sort.each {|v|
				puts("    #{dirList.index(v).to_s.rjust(2)}: #{v[0].ljust(32)} #{v[1][/\d{12}\.yaml$/][0..11] if v[1]}")
			} 

			print("done.\n\n") 
			print("Which host do you want?['all' for all]:")
			ans = gets().chomp()
			# TODO: entering a string that is not dirList.include? will return array[0], as to_f for a string = 0.0
		else
			ans = options[:hostname]
		end # if options[:hostname] == nil

		if ans == "all"
			checkedList = fileList
		elsif dirList.flatten.include?(ans)
			checkedList = process_files(reportDir + ans)[0]
		elsif dirList.flatten.include?(dirList.values_at(ans.to_f).flatten.fetch(0).to_s) and !(ans == "") 
			checkedList = process_files(reportDir + dirList.values_at(ans.to_f).flatten.fetch(0).to_s)[0]
		else
			raise "Invalid hostname selection"
		end

		rescue RuntimeError => e
			puts e
			retry
	end # options[:hostname] rescue block

	##
	# options[:hours] rescue block

	begin 
		if options[:hours] == nil
			print("\nHow many hours ago shall we check?:")
			ans = gets().chomp()

			if !(ans[/[0-9]+/]) then raise end

		else
			ans = options[:hours]
		end # if options[:hours] == nil
	
		timeFiltered = filter_by_time(checkedList,ans.to_f) 
		a = timeFiltered[0]
		puts("Found #{a.length} reports that are within time scope.") if options[:verbose]

		rescue
			puts "Error with time."
			retry
	end # options[:hours] rescue block

	##
	# options[:deleteolder] rescue block

	begin 
		if options[:deleteolder]
			olderfiles = timeFiltered[1]
			print "Deleting #{olderfiles.length.to_s} files..."

			olderfiles.each { |v| File.delete(v) }

			print "done."
			exit
		end #if options[:deleteolder]
		
	end # options[:deleteolder] rescue block

	##
	# options[:changes] rescue block
	
	begin 
		if options[:tagFilter] then tagFilter = options[:tagFilter] else tagFilter = nil end

		if options[:tagReverseFilter] then tagReverseFilter = options[:tagReverseFilter] else tagReverseFilter = nil end

		if !(options[:changes] or options[:logs] or options[:customMethods])
			puts("What information do you want?")
			print("\n\tc: Print host changes.")
			print("\n\tl: Print host logs.")
			print("\n\tR: Filter using custom query.")
			print("\n\tq: exit from this menu.\n")
			print("Enter your selection:")
			ans = gets().chomp()

			case ans
				when /c/
					parse_custom_methods('change_count > 0,failed')
					puts("Parsing reports using #{$customMethods.inspect}")
					print_host_changes(a, tagFilter, tagReverseFilter)
					print(tagFilter, tagReverseFilter)
					raise "Returning to menu"
				when /l/
					print_host_logs(a, tagFilter, tagReverseFilter)
					raise "Returning to menu"
				when /R/
					print("Enter custom query:")
					cMParam = gets().chomp()
					parse_custom_methods(cMParam)
					puts("Parsing reports using #{$customMethods.inspect}")
					print_host_changes(a, tagFilter, tagReverseFilter)
					raise "Returning to menu"
				when /q/
					do_nothing
			    else
					raise "Invalid selection"
			end # case ans

		else
			print("#{"Searching for tags " if tagFilter or tagReverseFilter}#{"matching: #{tagFilter}" if tagFilter}#{"not matching: #{tagReverseFilter}" if tagReverseFilter}\n") if $verbose
			print_host_changes(a, tagFilter, tagReverseFilter) if options[:changes]or options[:customMethods]
			print_host_logs(a, tagFilter, tagReverseFilter) if options[:logs]

		end # if !(options[:changes] or options[:logs])

		rescue RuntimeError => e
			puts e
			retry
	end # options[:changes] rescue block


	##
	# Break out into interactive session
	# http://bogojoker.com/readline/

	if options[:breakout] 
		require 'readline'

		puts("Summary information is hashed into: a, an array")
		puts("\n\nNo more code after this. Going interactive.")
		puts("Newline to eval.'q' to exit.") 
		program = ""
		input = ""
		line = ""

		until line.strip() == "q"
			line = Readline.readline('> ', true)

			begin # rescue block
				case( line.strip() )
					when '' 
						puts( "Evaluating..." )
						eval( input ) 
						input = ""
					else 
						input += line
				end #case

			rescue StandardError, SyntaxError => e
				puts("Error: " + e.to_s)
				input = ""
				retry
			end # rescue block

		end # until
	end # if options[:breakout]


##
# Rescue stuff

rescue SystemExit, Interrupt
	puts("\nQuitting.\n")
	exit
rescue StandardError => e
	puts("Error class: " + e.class.to_s)
	puts("Error: " + e.to_s )
	puts("Error backtrace: " + e.backtrace.to_s)

end # end main rescue block

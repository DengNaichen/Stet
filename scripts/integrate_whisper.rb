require 'xcodeproj'

project_path = 'Stet.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 1. Find the main target
target = project.targets.find { |t| t.name == 'Stet' }
unless target
  puts "Error: Could not find target 'Stet'"
  exit 1
end

# 2. Path to the built xcframework
xcframework_path = '.deps/whisper.cpp/build-apple/whisper.xcframework'
abs_xcframework_path = File.expand_path(xcframework_path)

unless File.exist?(abs_xcframework_path)
  puts "Error: #{xcframework_path} not found. Please run 'make whisper-deps' first."
  exit 1
end

# 3. Add the xcframework to the project (File Reference)
# We'll put it in a 'Frameworks' group
frameworks_group = project.main_group['Frameworks'] || project.main_group.new_group('Frameworks')
framework_ref = frameworks_group.files.find { |f| f.path == xcframework_path } || frameworks_group.new_file(xcframework_path)

# 4. Add to "Link Binary With Libraries"
build_phase = target.frameworks_build_phase
unless build_phase.files.find { |f| f.file_ref == framework_ref }
  build_phase.add_file_reference(framework_ref)
  puts "Added #{xcframework_path} to Link Binary With Libraries"
end

# 5. Add to "Embed Frameworks"
embed_phase = target.build_phases.find { |p| p.is_a?(Xcodeproj::Project::PBXCopyFilesBuildPhase) && p.name == 'Embed Frameworks' } ||
              target.new_copy_files_build_phase('Embed Frameworks')
embed_phase.dst_subfolder_spec = '10' # 10 is the Frameworks directory

unless embed_phase.files.find { |f| f.file_ref == framework_ref }
  build_file = embed_phase.add_file_reference(framework_ref)
  build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
  puts "Added #{xcframework_path} to Embed Frameworks"
end

# 6. Update Build Settings: FRAMEWORK_SEARCH_PATHS
target.build_configurations.each do |config|
  # Use parent directory of xcframework for search path
  search_path = '$(SRCROOT)/.deps/whisper.cpp/build-apple'
  
  framework_search_paths = Array(config.build_settings['FRAMEWORK_SEARCH_PATHS'])
  unless framework_search_paths.include?(search_path)
    config.build_settings['FRAMEWORK_SEARCH_PATHS'] = framework_search_paths << search_path
    puts "Added #{search_path} to FRAMEWORK_SEARCH_PATHS for config #{config.name}"
  end
end

project.save
puts "Successfully updated #{project_path}"

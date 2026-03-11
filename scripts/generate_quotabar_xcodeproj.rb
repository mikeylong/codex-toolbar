#!/usr/bin/env ruby

require 'fileutils'
require 'pathname'
require 'xcodeproj'

root = Pathname.new(File.expand_path('..', __dir__))
appstore_dir = root.join('AppStore')
project_path = appstore_dir.join('QuotaBar.xcodeproj')

FileUtils.rm_rf(project_path)
project = Xcodeproj::Project.new(project_path.to_s)
project.root_object.compatibility_version = 'Xcode 16.0'
project.root_object.attributes['LastSwiftUpdateCheck'] = '2600'
project.root_object.attributes['LastUpgradeCheck'] = '2600'

main_group = project.main_group
sources_group = main_group.find_subpath('Sources', true)
shared_group = sources_group.find_subpath('ToolbarCore', true)
quota_group = sources_group.find_subpath('QuotaBar', true)
resources_group = main_group.find_subpath('Resources', true)
config_group = main_group.find_subpath('Config', true)
site_group = main_group.find_subpath('Site', true)

shared_sources = [
  'Sources/CodexToolbar/App/ScreenshotScenario.swift',
  'Sources/CodexToolbar/App/StartupDiagnostics.swift',
  'Sources/CodexToolbar/Models/CodexRateLimits.swift',
  'Sources/CodexToolbar/Support/LoginItemController.swift',
  'Sources/CodexToolbar/Support/RateLimitClient.swift',
  'Sources/CodexToolbar/Support/RateLimitFormatter.swift',
  'Sources/CodexToolbar/Support/RateLimitStore.swift',
  'Sources/CodexToolbar/Support/ToolbarPresentation.swift',
  'Sources/CodexToolbar/Views/StatusMenuContentView.swift'
]

quota_sources = [
  'Sources/QuotaBar/QuotaBarApp.swift',
  'Sources/QuotaBar/QuotaBarPresentation.swift',
  'Sources/QuotaBar/QuotaBarRateLimitClient.swift',
  'Sources/QuotaBar/QuotaBarReleaseGate.swift',
  'Sources/QuotaBar/QuotaBarReviewDemo.swift'
]

resource_paths = [
  'Sources/QuotaBar/Resources/QuotaBarStatusGlyph.png',
  'AppStore/Resources/QuotaBar.icns',
  'AppStore/Resources/PrivacyInfo.xcprivacy'
]

config_paths = [
  'AppStore/Config/QuotaBar-Info.plist',
  'AppStore/Config/QuotaBar.entitlements'
]

site_paths = [
  'AppStore/site/index.html',
  'AppStore/site/privacy.html'
]

toolbar_core_target = project.new_target(:static_library, 'ToolbarCore', :osx, '14.0')
target = project.new_target(:application, 'QuotaBar', :osx, '14.0')

toolbar_core_target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_NAME'] = 'ToolbarCore'
  settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  settings['SWIFT_VERSION'] = '6.0'
  settings['DEFINES_MODULE'] = 'YES'
  settings['CLANG_ENABLE_MODULES'] = 'YES'
  settings['CLANG_ENABLE_OBJC_ARC'] = 'YES'
  settings['OTHER_SWIFT_FLAGS'] = ['$(inherited)', '-package-name', 'CodexToolbar']
end

target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_NAME'] = 'QuotaBar'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.mikelong.quotabar'
  settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  settings['INFOPLIST_FILE'] = 'Config/QuotaBar-Info.plist'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['CODE_SIGN_ENTITLEMENTS'] = 'Config/QuotaBar.entitlements'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['MARKETING_VERSION'] = '1.0.0'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['SWIFT_VERSION'] = '6.0'
  settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
  settings['ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS'] = 'NO'
  settings['CLANG_ENABLE_MODULES'] = 'YES'
  settings['CLANG_ENABLE_OBJC_ARC'] = 'YES'
  settings['OTHER_SWIFT_FLAGS'] = ['$(inherited)', '-package-name', 'CodexToolbar']
end

frameworks = ['Cocoa', 'SwiftUI', 'ServiceManagement']
frameworks.each do |framework|
  toolbar_core_target.add_system_framework(framework)
  target.add_system_framework(framework)
end

add_file = lambda do |group, path|
  relative_path = root.join(path).relative_path_from(appstore_dir).to_s
  group.new_file(relative_path)
end

shared_sources.each do |path|
  ref = add_file.call(shared_group, path)
  toolbar_core_target.add_file_references([ref])
end

quota_sources.each do |path|
  ref = add_file.call(quota_group, path)
  target.add_file_references([ref])
end

target.add_dependency(toolbar_core_target)
target.frameworks_build_phase.add_file_reference(toolbar_core_target.product_reference, true)

resource_paths.each do |path|
  ref = add_file.call(resources_group, path)
  target.resources_build_phase.add_file_reference(ref)
end

config_paths.each { |path| add_file.call(config_group, path) }
site_paths.each { |path| add_file.call(site_group, path) }

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(target, nil)
scheme.launch_action.build_configuration = 'Debug'
scheme.archive_action.build_configuration = 'Release'
scheme.save_as(project_path, 'QuotaBar', true)

project.save
puts "Generated #{project_path}"

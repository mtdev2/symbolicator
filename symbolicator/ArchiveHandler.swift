/*

Created by Tomaz Kragelj on 10.06.2014.
Copyright (c) 2014 Gentle Bytes. All rights reserved.

*/

import Foundation

class ArchiveHandler {
	init(path: String) {
		self.dwarfPathsByIdentifiers = Dictionary()
		self.basePath = path
	}
	
	/// Returns map where keys are names of binaries with corresponding full path to DWARF file.
	func dwarfPathWithIdentifier(identifier: String, version: String, build: String) -> String? {
		// If we don't have any dwarf files scanned, do so now.
		if self.dwarfPathsByIdentifiers.count == 0 {
			let manager = NSFileManager.defaultManager()
			let fullBasePath = (self.basePath as NSString).stringByStandardizingPath
			manager.enumerateDirectoriesAtPath(fullBasePath) { dateFolder in
				manager.enumerateDirectoriesAtPath(dateFolder) { buildFolder in
					// If there's no plist file at the given path, ignore it.
					let plistPath = (buildFolder as NSString).stringByAppendingPathComponent("Info.plist")
					if !manager.fileExistsAtPath(plistPath) { return }
					
					// Load plist into dictionary.
					let plistData = try! NSData(contentsOfFile: plistPath, options: .DataReadingUncached)
					let plistContents: AnyObject = try! NSPropertyListSerialization.propertyListWithData(plistData, options: NSPropertyListReadOptions(rawValue: 0), format: nil)
					
					// Read application properties.
					let applicationInfo = self.applicationInformationWithInfoPlist(plistContents)
					
					// Scan for all subfolders of dSYMs folder.
					manager.enumerateDirectoriesAtPath("\(buildFolder)/dSYMs") { subpath in
						// Delete .app.dSYM or .framework.dSYM and prepare path to contained DWARF file.
						let binaryNameWithExtension = ((subpath as NSString).lastPathComponent as NSString).stringByDeletingPathExtension
						let binaryName = (binaryNameWithExtension as NSString).stringByDeletingPathExtension
						let dwarfPath = "\(subpath)/Contents/Resources/DWARF/\(binaryName)"
						
						// Add the key to DWARF file for this binary.
						let dwarfKey = self.dwarfKeyWithIdentifier(binaryName, version: applicationInfo.version, build: applicationInfo.build)
						self.dwarfPathsByIdentifiers[dwarfKey] = dwarfPath
						
						// If this is the main application binary, also create the key with bundle identifier.
						if binaryNameWithExtension == applicationInfo.name {
							let identifierKey = self.dwarfKeyWithIdentifier(applicationInfo.identifier, version: applicationInfo.version, build: applicationInfo.build)
							self.dwarfPathsByIdentifiers[identifierKey] = dwarfPath
						}
					}
				}
			}
		}
		
		// Try to get dwarf path using build number first. If found, use it.
		let archiveKey = self.dwarfKeyWithIdentifier(identifier, version: version, build: build)
		if let result = self.dwarfPathsByIdentifiers[archiveKey] {
			return result
		}
		
		// Try to use generic "any build" for given version (older versions of Xcode didn't save build number to archive plist). If found, use it.
		let genericArchiveKey = self.dwarfKeyWithIdentifier(identifier, version: version, build: "")
		if let result = self.dwarfPathsByIdentifiers[genericArchiveKey] {
			return result
		}
		
		// If there's no archive match, return nil
		return nil
	}
	
	private func applicationInformationWithInfoPlist(plistContents: AnyObject) -> (name: String, identifier: String, version: String, build: String) {
		var applicationName = ""
		var applicationIdentifier = ""
		var applicationVersion = ""
		var applicationBuild = ""
		
		if let applicationProperties: AnyObject = plistContents.objectForKey("ApplicationProperties") {
			if let path = applicationProperties.objectForKey("ApplicationPath") as? String {
				applicationName = (path as NSString).lastPathComponent
			}
			if let identifier = applicationProperties.objectForKey("CFBundleIdentifier") as? String {
				applicationIdentifier = identifier
			}
			if let version = applicationProperties.objectForKey("CFBundleShortVersionString") as? String {
				applicationVersion = version
			}
			if let build = applicationProperties.objectForKey("CFBundleVersion") as? String {
				applicationBuild = build
			}
		}
		
		return (applicationName, applicationIdentifier, applicationVersion, applicationBuild)
	}
	
	private func dwarfKeyWithIdentifier(identifier: String, version: String, build: String) -> String {
		if build.characters.count == 0 {
			return "\(identifier) \(version) ANYBUILD"
		}
		return "\(identifier) \(version) \(build)"
	}
	
	private let basePath: String
	private var dwarfPathsByIdentifiers: Dictionary<String, String>
}

extension NSFileManager {
	func enumerateDirectoriesAtPath(path: String, block: (path: String) -> Void) {
		let subpaths = try! self.contentsOfDirectoryAtPath(path) as [String]
		for subpath in subpaths {
			let fullPath = (path as NSString).stringByAppendingPathComponent(subpath)
			if !self.isDirectoryAtPath(fullPath) { continue }
			block(path: fullPath)
		}
	}
	
	func isDirectoryAtPath(path: NSString) -> Bool {
		let attributes = try! self.attributesOfItemAtPath(path as String)
		if attributes[NSFileType] as? NSObject == NSFileTypeDirectory {
			return true
		}
		return false
	}
}

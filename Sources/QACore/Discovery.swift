import Foundation

public enum ProjectKind: String {
    case workspace
    case project
    case package
}

public struct ProjectReference {
    public let path: String
    public let kind: ProjectKind
}

// Why: a workspace can wrap a project, so it's the broadest container and takes priority when both are present.
public func discoverProject(in directory: String) -> ProjectReference? {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
        return nil
    }

    if let name = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
        return ProjectReference(path: "\(directory)/\(name)", kind: .workspace)
    }
    if let name = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
        return ProjectReference(path: "\(directory)/\(name)", kind: .project)
    }
    if contents.contains("Package.swift") {
        return ProjectReference(path: "\(directory)/Package.swift", kind: .package)
    }
    return nil
}

// Why: -list -json is a stable shape to parse instead of scraping xcodebuild's human-readable text output.
public func listSchemes(for project: ProjectReference) -> [String] {
    var arguments = ["xcodebuild", "-list", "-json"]
    var workingDirectory: String?

    switch project.kind {
    case .workspace:
        arguments += ["-workspace", project.path]
    case .project:
        arguments += ["-project", project.path]
    case .package:
        workingDirectory = (project.path as NSString).deletingLastPathComponent
    }

    let result = shell("xcrun", arguments, workingDirectory: workingDirectory)
    guard result.exitCode == 0,
          let data = result.output.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return []
    }

    let container = (json["workspace"] ?? json["project"]) as? [String: Any]
    return container?["schemes"] as? [String] ?? []
}

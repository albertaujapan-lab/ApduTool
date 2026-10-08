//
//  Script.swift
//  ApduTool
//
//  Created by Ken Cheung on 4/8/24.
//

import Foundation

class Script {
    func parseFile(atPath path: String) -> [String] {
        do {
            let fileContents = try String(contentsOfFile: path, encoding: .utf8)
            let lines = fileContents.components(separatedBy: .newlines)
            var parsedLines: [String] = []
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanLine = trimmedLine.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !cleanLine.isEmpty {
                    parsedLines.append(cleanLine)
                }
            }
            
            return parsedLines
        } catch {
            print("Error reading file: \(error)")
            return []
        }
    }
}

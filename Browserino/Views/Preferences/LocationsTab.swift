//  BrowserSearchLocationsTab.swift
//  Browserino
//
//  Created by byt3m4st3r.
//

import SwiftUI

struct Directory: Codable, Hashable {
    var directoryPath: String
}

struct BrowserLocationsSection: View {
    @AppStorage("directories") private var directories: [Directory] = []
    @State private var explorerPresented = false

    var body: some View {
        Section {
            ForEach(directories, id: \.self) { directory in
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(directory.directoryPath)
                        .truncationMode(.middle)
                    Spacer()
                    if directory.directoryPath != "/Applications" {
                        Button {
                            directories.removeAll { $0 == directory }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop looking in this folder")
                    }
                }
            }

            Button("Add Folder…") {
                explorerPresented.toggle()
            }
            .fileImporter(
                isPresented: $explorerPresented,
                allowedContentTypes: [.directory]
            ) { result in
                if case let .success(directory) = result {
                    let newDirectory = Directory(directoryPath: directory.path)
                    if !directories.contains(newDirectory) {
                        directories.append(newDirectory)
                    }
                }
            }
        } header: {
            Text("Where to look for browsers")
                .settingsItem("browsers.locations")
        } footer: {
            Text("Linkyard lists the browsers installed in these folders. Rescan after adding one.")
        }
        .onAppear {
            if directories.isEmpty {
                directories.append(Directory(directoryPath: "/Applications"))
            }
        }
    }
}

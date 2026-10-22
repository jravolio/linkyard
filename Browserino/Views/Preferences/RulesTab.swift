//
//  RulesTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import SwiftUI

struct AddRule: View {
    @State private var addPresented = false
    
    var body: some View {
        HStack {
            Image(systemName: "plus")
                .font(
                    .system(size: 14)
                )
                .opacity(0)
            
            Text("Add a rule by matching a URL, optional source app/window, and selecting a target app.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
                .frame(width: 16)
            
            Button(action: {
                addPresented.toggle()
            }) {
                Text("Add new rule")
            }
            .sheet(isPresented: $addPresented) {
                NewRuleForm(
                    isPresented: $addPresented
                )
            }
        }
    }
}

struct RuleItem: View {
    @Binding var rule: Rule
    @State private var editPresented = false

    private var sourceDescription: String? {
        var parts: [String] = []

        if let sourceApp = rule.sourceApp, Bundle(url: sourceApp) != nil {
            parts.append("from \(sourceApp.appDisplayName)")
        }

        if let sourceWindowTitleRegex = rule.sourceWindowTitleRegex,
           !sourceWindowTitleRegex.isEmpty {
            parts.append("window matches /\(sourceWindowTitleRegex)/")
        }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
    
    var body: some View {
        let bundle = Bundle(url: rule.app)!

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Button(action: {
                    editPresented.toggle()
                }) {
                    Label(rule.regex, systemImage: "pencil")
                        .font(
                            .system(size: 14)
                        )
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                if let sourceDescription {
                    Text(sourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
             
            Spacer()
            
            
            Text(bundle.infoDictionary!["CFBundleName"] as! String)
                .font(
                    .system(size: 14)
                )
            
            
            Spacer()
                .frame(width: 8)
            
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundle.bundlePath))
                .resizable()
                .frame(width: 32, height: 32)
        }
        .padding(10)
        .sheet(isPresented: $editPresented) {
            EditRuleForm(
                rule: $rule,
                isPresented: $editPresented
            )
        }
    }
}

struct RulesTab: View {
    @AppStorage("rules") private var rules: [Rule] = []
    
    var body: some View {
        VStack (alignment: .leading) {
            List {
                AddRule()

                ForEach(Array($rules.enumerated()), id: \.offset) { offset, rule in
                    RuleItem(
                        rule: rule
                    )
                }
            }
            
            Text("Type a URL regex and choose where matching links open. Source conditions can route links from specific apps or Slack workspaces.")
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.5))
                .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 20)
    }
}

#Preview {
    RulesTab()
}

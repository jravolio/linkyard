//
//  AppleEvents.swift
//  Browserino
//

import AppKit

/// Builds Apple Events by hand. NSAppleScript loads the AppleScript runtime, which keeps ~13 MB resident and takes
/// ~100 ms the first time, so Dia, which can get a link on every click, is sent raw events instead.
/// Event and type codes come from the app's scripting dictionary (`sdef /Applications/Dia.app`).
enum AppleEvents {
    static func code(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }

    static func type(_ name: String) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(typeCode: code(name))
    }

    static func record(_ fields: [String: NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        for (keyword, value) in fields {
            record.setDescriptor(value, forKeyword: code(keyword))
        }
        return record
    }

    static func element(_ want: String, at index: Int32, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        specifier(want, form: "indx", NSAppleEventDescriptor(int32: index), of: container)
    }

    static func every(_ want: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        var all = code("all ")
        return specifier(want, form: "indx", NSAppleEventDescriptor(descriptorType: code("abso"), bytes: &all, length: 4)!, of: container)
    }

    static func property(_ name: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier("prop", form: "prop", type(name), of: container)
    }

    /// `first <want> whose name is <name>`; `send` makes the comparison ignore case, as AppleScript does.
    static func named(_ want: String, _ name: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let test = record([
            "relo": NSAppleEventDescriptor(enumCode: code("=   ")),
            "obj1": property("pnam", of: NSAppleEventDescriptor(descriptorType: code("exmn"), data: nil)!),
            "obj2": NSAppleEventDescriptor(string: name),
        ])
        let matching = specifier(want, form: "test", test.coerce(toDescriptorType: code("cmpd"))!, of: container)
        return element(want, at: 1, of: matching)
    }

    static func end(of elements: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        record([
            "kobj": elements,
            "kpos": NSAppleEventDescriptor(enumCode: code("end ")),
        ]).coerce(toDescriptorType: code("insl"))!
    }

    /// Throws when the app can't be reached or answers with an error, like a script error would.
    /// An app handles one sender's events in order, so a later event still runs after one sent without waiting.
    @discardableResult
    static func send(
        _ eventClass: String,
        _ eventID: String,
        to bundleID: String,
        _ parameters: [String: NSAppleEventDescriptor] = [:],
        waitsForReply: Bool = true
    ) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: code(eventClass),
            eventID: code(eventID),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        for (keyword, value) in parameters {
            event.setParam(value, forKeyword: code(keyword))
        }
        // kAECaseIgnoreMask, which AppleScript sends by default.
        event.setAttribute(NSAppleEventDescriptor(int32: 0x0001_0000), forKeyword: code("csig"))

        // AppleScript's default timeout, long enough to answer the first Automation prompt.
        let reply = try event.sendEvent(options: waitsForReply ? .waitForReply : .noReply, timeout: 120)
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        return reply
    }

    private static func specifier(
        _ want: String,
        form: String,
        _ data: NSAppleEventDescriptor,
        of container: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        record([
            "want": type(want),
            "form": NSAppleEventDescriptor(enumCode: code(form)),
            "seld": data,
            "from": container,
        ]).coerce(toDescriptorType: code("obj "))!
    }
}

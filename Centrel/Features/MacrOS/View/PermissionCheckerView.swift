//
//  PermissionCheckerView.swift
//  Centrel
//
//  Created by Max Weißenbäck on 03.05.25.
//

import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid

struct PermissionCheckerView: View {
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var inputMonitoringGranted: Bool = (IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Permission Status")
                .font(.headline)

            HStack {
                Text("Accessibility:")
                Spacer()
                Text(accessibilityGranted ? "✅ Granted" : "❌ Denied")
            }
            HStack {
                Text("Input Monitoring:")
                Spacer()
                Text(inputMonitoringGranted ? "✅ Granted" : "❌ Denied")
            }

            Divider()

            Button("Open Accessibility Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Open Input Monitoring Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_InputMonitoring") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

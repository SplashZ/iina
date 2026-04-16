//
//  PrefNetworkViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefNetworkViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefNetworkViewController")
  }

  var viewIdentifier: String = "PrefNetworkViewController"

  var preferenceTabImage: NSImage {
    return makeSymbol("network", fallbackImage: "pref_network")
  }

  var preferenceTabTitle: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.network", comment: "Network")
  }

  @IBOutlet weak var ytdlHelpLabel: NSTextField!
  @IBOutlet weak var enableYTDLCheckBox: NSButton!

  override var sectionViews: [NSView] {
    return [sectionCacheView, sectionNetworkView, sectionYTDLView, castingSectionView]
  }

  @IBOutlet var sectionCacheView: NSView!
  @IBOutlet var sectionNetworkView: NSView!
  @IBOutlet var sectionYTDLView: NSView!

  // MARK: - Casting Section (programmatic)

  private lazy var castingSectionView: NSView = buildCastingSection()

  private func buildCastingSection() -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    // Section title
    let title = NSTextField(labelWithString: NSLocalizedString("preference.casting", comment: "Casting"))
    title.font = .boldSystemFont(ofSize: 13)
    title.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(title)

    // HTTP Port row
    let portLabel = NSTextField(labelWithString: NSLocalizedString("preference.casting.http_port", comment: "Local HTTP Port"))
    portLabel.alignment = .right
    portLabel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(portLabel)

    let portField = NSTextField()
    portField.translatesAutoresizingMaskIntoConstraints = false
    portField.stringValue = "\(Preference.integer(for: .castingHTTPPort))"
    portField.formatter = {
      let f = NumberFormatter()
      f.minimum = 1024
      f.maximum = 65535
      f.allowsFloats = false
      return f
    }()
    portField.target = self
    portField.action = #selector(portFieldChanged(_:))
    container.addSubview(portField)

    // Discovery timeout row
    let timeoutLabel = NSTextField(labelWithString: NSLocalizedString("preference.casting.discovery_timeout", comment: "Discovery Timeout (s)"))
    timeoutLabel.alignment = .right
    timeoutLabel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(timeoutLabel)

    let timeoutField = NSTextField()
    timeoutField.translatesAutoresizingMaskIntoConstraints = false
    timeoutField.stringValue = "\(Preference.integer(for: .castingDiscoveryTimeout))"
    timeoutField.formatter = {
      let f = NumberFormatter()
      f.minimum = 3
      f.maximum = 60
      f.allowsFloats = false
      return f
    }()
    timeoutField.target = self
    timeoutField.action = #selector(timeoutFieldChanged(_:))
    container.addSubview(timeoutField)

    // Layout
    let labelWidth: CGFloat = 180
    let fieldWidth: CGFloat = 80

    NSLayoutConstraint.activate([
      title.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
      title.leadingAnchor.constraint(equalTo: container.leadingAnchor),

      portLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
      portLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
      portLabel.widthAnchor.constraint(equalToConstant: labelWidth),
      portLabel.centerYAnchor.constraint(equalTo: portField.centerYAnchor),

      portField.leadingAnchor.constraint(equalTo: portLabel.trailingAnchor, constant: 8),
      portField.topAnchor.constraint(equalTo: portLabel.topAnchor),
      portField.widthAnchor.constraint(equalToConstant: fieldWidth),

      timeoutLabel.topAnchor.constraint(equalTo: portLabel.bottomAnchor, constant: 10),
      timeoutLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
      timeoutLabel.widthAnchor.constraint(equalToConstant: labelWidth),
      timeoutLabel.centerYAnchor.constraint(equalTo: timeoutField.centerYAnchor),

      timeoutField.leadingAnchor.constraint(equalTo: timeoutLabel.trailingAnchor, constant: 8),
      timeoutField.topAnchor.constraint(equalTo: timeoutLabel.topAnchor),
      timeoutField.widthAnchor.constraint(equalToConstant: fieldWidth),

      container.bottomAnchor.constraint(equalTo: timeoutField.bottomAnchor, constant: 12),
    ])

    return container
  }

  @objc private func portFieldChanged(_ sender: NSTextField) {
    if let val = Int(sender.stringValue), (1024...65535).contains(val) {
      Preference.set(val, for: .castingHTTPPort)
    }
  }

  @objc private func timeoutFieldChanged(_ sender: NSTextField) {
    if let val = Int(sender.stringValue), (3...60).contains(val) {
      Preference.set(val, for: .castingDiscoveryTimeout)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    updateYTDLSettings()
    NotificationCenter.default.addObserver(forName: .iinaPluginChanged, object: nil, queue: .main) { [unowned self] _ in
      self.updateYTDLSettings()
    }
  }

  private func updateYTDLSettings() {
    let hasYTDL = JavascriptPlugin.hasYTDL
    enableYTDLCheckBox.state = hasYTDL ? .off : (Preference.bool(for: .ytdlEnabled) ? .on : .off)
    sectionYTDLView.subviews.forEach {
      if let control = $0 as? NSControl {
        control.isEnabled = !hasYTDL
      }
    }
    ytdlHelpLabel.stringValue = hasYTDL ?
      NSLocalizedString("preference.ytdl_plugin_installed", comment: "") :
      NSLocalizedString("preference.ytdl_plugin_not_installed", comment: "")
  }

  @IBAction func ytdlHelpAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.ytdlHelpLink)!)
  }

}

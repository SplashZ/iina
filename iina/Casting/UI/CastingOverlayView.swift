import AppKit

/// A full-window overlay shown while casting, matching the visual appearance of the PiP overlay.
/// Uses NSVisualEffectView so it looks identical to the PiP state.
/// It is inserted below the OSC in z-order so playback controls remain interactive.
final class CastingOverlayView: NSVisualEffectView {
  private let iconView = NSImageView()
  private let deviceLabel = NSTextField(labelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")
  private var stateObserver: NSObjectProtocol?

  override init(frame: NSRect) {
    super.init(frame: frame)
    setup()
    stateObserver = NotificationCenter.default.addObserver(
      forName: .castingStateDidChange, object: nil, queue: .main
    ) { [weak self] note in
      // Hop onto @MainActor so mgr.state is accessed within the actor's isolation context.
      Task { @MainActor [weak self] in
        guard let self,
              let mgr = note.object as? CastingManager,
              case .casting(let session) = mgr.state else { return }
        self.updateStatus(session.isSwitchingAudio)
      }
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit {
    if let obs = stateObserver { NotificationCenter.default.removeObserver(obs) }
  }

  private func setup() {
    material = .underWindowBackground
    blendingMode = .behindWindow
    state = .active

    if #available(macOS 11.0, *) {
      iconView.image = NSImage(systemSymbolName: "airplayvideo", accessibilityDescription: nil)
    } else {
      iconView.image = NSImage(named: NSImage.Name("cast"))
    }
    iconView.contentTintColor = .labelColor
    iconView.imageScaling = .scaleProportionallyUpOrDown
    iconView.translatesAutoresizingMaskIntoConstraints = false

    deviceLabel.textColor = .secondaryLabelColor
    deviceLabel.font = .systemFont(ofSize: 13)
    deviceLabel.alignment = .center
    deviceLabel.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.textColor = .secondaryLabelColor
    statusLabel.font = .systemFont(ofSize: 11)
    statusLabel.alignment = .center
    statusLabel.isHidden = true
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    [iconView, deviceLabel, statusLabel].forEach { addSubview($0) }

    NSLayoutConstraint.activate([
      iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
      iconView.widthAnchor.constraint(equalToConstant: 72),
      iconView.heightAnchor.constraint(equalToConstant: 72),

      deviceLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      deviceLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
      deviceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
      deviceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

      statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      statusLabel.topAnchor.constraint(equalTo: deviceLabel.bottomAnchor, constant: 6),
      statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
      statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
    ])
  }

  private func updateStatus(_ switching: Bool) {
    if switching {
      statusLabel.stringValue = NSLocalizedString(
        "casting.osd.switching_audio", comment: "正在切换音轨...")
      statusLabel.isHidden = false
    } else {
      statusLabel.isHidden = true
    }
  }

  /// 让覆盖层对鼠标事件完全透明，点击穿透到下层 VideoView，
  /// 使侧边抽屉的"点外部收起"逻辑正常工作。
  override func hitTest(_ point: NSPoint) -> NSView? {
    return nil
  }

  func update(deviceName: String) {
    deviceLabel.stringValue = deviceName
  }
}

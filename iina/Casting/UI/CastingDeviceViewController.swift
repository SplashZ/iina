import AppKit

/// 投屏设备选择侧边栏视图控制器。
/// 支持四种显示状态：扫描中（无设备）、设备列表、空状态、投屏中。
final class CastingDeviceViewController: NSViewController, SidebarViewController {

  // MARK: - SidebarViewController

  var downShift: CGFloat = 0 {
    didSet {
      loadingTopConstraint?.constant = downShift
      listTopConstraint?.constant = downShift
      emptyTopConstraint?.constant = downShift
      castingTopConstraint?.constant = downShift
    }
  }

  // MARK: - Loading view（扫描中且无设备时居中显示）

  private let loadingContainer = NSView()
  private var loadingTopConstraint: NSLayoutConstraint?

  private let spinner = NSProgressIndicator()
  private let loadingLabel = NSTextField(labelWithString: "")

  // MARK: - Device list view（有设备时显示）

  private let listContainer = NSView()
  private var listTopConstraint: NSLayoutConstraint?

  private let scrollView = NSScrollView()
  private let tableView = NSTableView()
  private let refreshButton = NSButton()

  // MARK: - Empty view（扫描结束且无设备时显示）

  private let emptyContainer = NSView()
  private var emptyTopConstraint: NSLayoutConstraint?

  private let emptyLabel = NSTextField(labelWithString: "")
  private let emptyRefreshButton = NSButton()

  // MARK: - Casting view（投屏中显示）

  private let castingContainer = NSView()
  private var castingTopConstraint: NSLayoutConstraint?

  private let castingDeviceLabel = NSTextField(labelWithString: "")
  private let stopButton = NSButton()

  // MARK: - State

  private var stateObserver: NSObjectProtocol?
  private var deviceRows: [any CastingDevice] = []
  weak var mainWindow: MainWindowController?

  // MARK: - Lifecycle

  override func loadView() {
    view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    setupUI()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    let m = CastingManager.shared
    updateUI(state: m.state, isScanning: m.isScanning)
    stateObserver = NotificationCenter.default.addObserver(
      forName: .castingStateDidChange, object: nil, queue: .main
    ) { [weak self] note in
      Task { @MainActor [weak self] in
        guard let self, let mgr = note.object as? CastingManager else { return }
        self.updateUI(state: mgr.state, isScanning: mgr.isScanning)
      }
    }
  }

  deinit {
    if let obs = stateObserver { NotificationCenter.default.removeObserver(obs) }
  }

  // MARK: - Setup

  private func setupUI() {
    setupLoadingView()
    setupListView()
    setupEmptyView()
    setupCastingView()
  }

  private func setupLoadingView() {
    loadingContainer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(loadingContainer)

    let top = loadingContainer.topAnchor.constraint(equalTo: view.topAnchor)
    loadingTopConstraint = top
    NSLayoutConstraint.activate([
      top,
      loadingContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      loadingContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      loadingContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    // Spinner（large size，居中）
    spinner.style = .spinning
    spinner.controlSize = .regular
    spinner.isDisplayedWhenStopped = false
    spinner.translatesAutoresizingMaskIntoConstraints = false

    loadingLabel.stringValue = NSLocalizedString("casting.scanning", comment: "搜索投屏设备...")
    loadingLabel.textColor = .secondaryLabelColor
    loadingLabel.font = .systemFont(ofSize: 13)
    loadingLabel.alignment = .center

    let stack = NSStackView(views: [spinner, loadingLabel])
    stack.orientation = .vertical
    stack.spacing = 10
    stack.alignment = .centerX
    stack.translatesAutoresizingMaskIntoConstraints = false

    loadingContainer.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: loadingContainer.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: loadingContainer.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: loadingContainer.trailingAnchor, constant: -16),
    ])
  }

  private func setupListView() {
    listContainer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(listContainer)

    let top = listContainer.topAnchor.constraint(equalTo: view.topAnchor)
    listTopConstraint = top
    NSLayoutConstraint.activate([
      top,
      listContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      listContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      listContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    // Table
    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("device"))
    col.title = ""
    col.resizingMask = .autoresizingMask
    tableView.addTableColumn(col)
    tableView.headerView = nil
    tableView.rowHeight = 36
    tableView.delegate = self
    tableView.dataSource = self
    tableView.selectionHighlightStyle = .regular
    tableView.backgroundColor = .clear
    tableView.focusRingType = .none
    tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    tableView.gridStyleMask = .solidHorizontalGridLineMask
    tableView.gridColor = .separatorColor

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    // Refresh button（底部固定栏）
    refreshButton.title = NSLocalizedString("casting.refresh_plain", comment: "刷新")
    refreshButton.bezelStyle = .inline
    refreshButton.controlSize = .small
    refreshButton.target = self
    refreshButton.action = #selector(refreshDevices)
    refreshButton.translatesAutoresizingMaskIntoConstraints = false

    let bottomBar = NSView()
    bottomBar.translatesAutoresizingMaskIntoConstraints = false
    bottomBar.addSubview(refreshButton)
    NSLayoutConstraint.activate([
      refreshButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
      refreshButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
      bottomBar.heightAnchor.constraint(equalToConstant: 36),
    ])

    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false

    listContainer.addSubview(scrollView)
    listContainer.addSubview(separator)
    listContainer.addSubview(bottomBar)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: listContainer.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

      separator.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
      separator.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

      bottomBar.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
      bottomBar.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
      bottomBar.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
    ])
  }

  private func setupEmptyView() {
    emptyContainer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(emptyContainer)

    let top = emptyContainer.topAnchor.constraint(equalTo: view.topAnchor)
    emptyTopConstraint = top
    NSLayoutConstraint.activate([
      top,
      emptyContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      emptyContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      emptyContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    emptyLabel.stringValue = NSLocalizedString("casting.no_devices", comment: "未发现设备")
    emptyLabel.textColor = .tertiaryLabelColor
    emptyLabel.font = .systemFont(ofSize: 13)
    emptyLabel.alignment = .center

    emptyRefreshButton.title = NSLocalizedString("casting.refresh_plain", comment: "刷新")
    emptyRefreshButton.bezelStyle = .rounded
    emptyRefreshButton.target = self
    emptyRefreshButton.action = #selector(refreshDevices)

    let stack = NSStackView(views: [emptyLabel, emptyRefreshButton])
    stack.orientation = .vertical
    stack.spacing = 12
    stack.alignment = .centerX
    stack.translatesAutoresizingMaskIntoConstraints = false

    emptyContainer.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyContainer.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: emptyContainer.trailingAnchor, constant: -16),
    ])
  }

  private func setupCastingView() {
    castingContainer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(castingContainer)

    let top = castingContainer.topAnchor.constraint(equalTo: view.topAnchor)
    castingTopConstraint = top
    NSLayoutConstraint.activate([
      top,
      castingContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      castingContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      castingContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    castingDeviceLabel.font = .systemFont(ofSize: 13)
    castingDeviceLabel.textColor = .labelColor
    castingDeviceLabel.alignment = .center
    castingDeviceLabel.lineBreakMode = .byTruncatingTail
    castingDeviceLabel.maximumNumberOfLines = 2

    stopButton.title = NSLocalizedString("casting.stop", comment: "停止投屏")
    stopButton.bezelStyle = .rounded
    stopButton.target = self
    stopButton.action = #selector(stopCasting)

    let stack = NSStackView(views: [castingDeviceLabel, stopButton])
    stack.orientation = .vertical
    stack.spacing = 12
    stack.alignment = .centerX
    stack.translatesAutoresizingMaskIntoConstraints = false

    castingContainer.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: castingContainer.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: castingContainer.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: castingContainer.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: castingContainer.trailingAnchor, constant: -16),
    ])
  }

  // MARK: - State Update

  private func updateUI(state: CastingState, isScanning: Bool) {
    switch state {
    case .casting(let session):
      loadingContainer.isHidden = true
      listContainer.isHidden = true
      emptyContainer.isHidden = true
      castingContainer.isHidden = false
      castingDeviceLabel.stringValue = String(
        format: NSLocalizedString("casting.casting_to", comment: "正在投屏到 %@"),
        session.device.name
      )

    case .discovering(let devices):
      castingContainer.isHidden = true
      deviceRows = devices
      tableView.reloadData()
      // 调整 tableView 列宽以填满
      if tableView.superview != nil {
        tableView.tableColumns.first?.width = scrollView.frame.width
      }
      let hasDevices = !devices.isEmpty
      if hasDevices {
        // 有设备：显示列表（扫描期间 loading 叠在上方）
        loadingContainer.isHidden = true
        listContainer.isHidden = false
        emptyContainer.isHidden = true
      } else if isScanning {
        // 扫描中且无设备：居中显示 loading
        loadingContainer.isHidden = false
        listContainer.isHidden = true
        emptyContainer.isHidden = true
      } else {
        // 扫描结束且无设备
        loadingContainer.isHidden = true
        listContainer.isHidden = true
        emptyContainer.isHidden = false
      }

    case .connecting:
      // Sidebar is about to close; keep the current device list visible without flashing to empty state.
      return

    case .idle, .error:
      castingContainer.isHidden = true
      if isScanning {
        loadingContainer.isHidden = false
        listContainer.isHidden = true
        emptyContainer.isHidden = true
      } else {
        loadingContainer.isHidden = true
        listContainer.isHidden = true
        emptyContainer.isHidden = false
      }
    }

    // 根据 loadingContainer 可见性控制 spinner 动画
    if loadingContainer.isHidden {
      spinner.stopAnimation(nil)
    } else {
      spinner.startAnimation(nil)
    }
  }

  // MARK: - Actions

  @objc private func refreshDevices() {
    CastingManager.shared.beginDiscoveryForPicker()
  }

  @objc private func stopCasting() {
    Task { await CastingManager.shared.stopCasting() }
    mainWindow?.hideSideBar()
  }
}

// MARK: - NSTableViewDataSource / NSTableViewDelegate

extension CastingDeviceViewController: NSTableViewDataSource, NSTableViewDelegate {

  func numberOfRows(in tableView: NSTableView) -> Int { deviceRows.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                 row: Int) -> NSView? {
    let device = deviceRows[row]
    let cellId = NSUserInterfaceItemIdentifier("DeviceCell")
    var cell = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView
    if cell == nil {
      let tf = NSTextField(labelWithString: "")
      tf.font = .systemFont(ofSize: 13)
      tf.textColor = .labelColor
      tf.lineBreakMode = .byTruncatingTail
      let c = NSTableCellView()
      c.textField = tf
      c.identifier = cellId
      c.addSubview(tf)
      tf.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 12),
        tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -12),
        tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
      ])
      cell = c
    }
    cell?.textField?.stringValue = device.name
    return cell
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    !CastingManager.shared.isCasting
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard row >= 0, row < deviceRows.count else { return }
    let device = deviceRows[row]
    tableView.deselectAll(nil)
    // Use the player that owns this window rather than PlayerCore.active, which
    // relies on NSApp.mainWindow and may return the wrong instance when the
    // frontmost window is not a player window.
    guard let playerCore = mainWindow?.player else { return }
    CastingManager.shared.beginCasting(to: device, playerCore: playerCore)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      self?.mainWindow?.hideSideBar()
    }
  }
}

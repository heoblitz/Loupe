import SwiftUI
import Security
import UIKit
import WebKit

struct ExampleItem {
    let index: Int
    let title: String
    let subtitle: String
    let status: String
}

final class ViewController: UITableViewController {
    private let allItems: [ExampleItem] = (1...80).map {
        ExampleItem(
            index: $0,
            title: "Customer \($0)",
            subtitle: $0.isMultiple(of: 3) ? "Needs follow-up" : "Ready for review",
            status: $0.isMultiple(of: 2) ? "Open" : "Draft"
        )
    }

    private var visibleItems: [ExampleItem] = []
    private let searchController = UISearchController(searchResultsController: nil)
    private var didSendLoupeBridgeExample = false

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Loupe Workbench"
        visibleItems = allItems
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Components",
            style: .plain,
            target: self,
            action: #selector(openComponents)
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "example.openComponents"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Form",
            style: .plain,
            target: self,
            action: #selector(openForm)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "example.openForm"

        tableView.register(ExampleCell.self, forCellReuseIdentifier: ExampleCell.reuseIdentifier)
        tableView.accessibilityIdentifier = "example.customerList"
        tableView.rowHeight = 76
        tableView.tableHeaderView = fixtureHeaderView()

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search customers"
        searchController.searchBar.accessibilityIdentifier = "example.search"
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sendLoupeBridgeExampleIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let header = tableView.tableHeaderView, header.bounds.width != tableView.bounds.width else {
            return
        }

        var frame = header.frame
        frame.size.width = tableView.bounds.width
        header.frame = frame
        if let button = header.subviews.first(where: { $0.accessibilityIdentifier == "example.openFixtures" }) {
            button.frame = CGRect(x: 20, y: 10, width: max(tableView.bounds.width - 40, 0), height: 48)
        }
        tableView.tableHeaderView = header
    }

    private func sendLoupeBridgeExampleIfNeeded() {
        guard !didSendLoupeBridgeExample else {
            return
        }
        didSendLoupeBridgeExample = true

        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.log"),
            object: nil,
            userInfo: [
                "level": "info",
                "message": "example_customers_visible",
                "metadata": ["screen": "customers"]
            ]
        )
        DispatchQueue.global(qos: .utility).async {
            NotificationCenter.default.post(
                name: Notification.Name("dev.loupe.log"),
                object: nil,
                userInfo: [
                    "level": "info",
                    "message": "example_customers_background_visible",
                    "metadata": [
                        "screen": "customers",
                        "origin": "background"
                    ]
                ]
            )
        }
        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.viewMetadata"),
            object: tableView,
            userInfo: [
                "metadata": [
                    "screen": "customers",
                    "fixture": true
                ]
            ]
        )
        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.network"),
            object: nil,
            userInfo: [
                "method": "GET",
                "url": "https://api.example.test/customers",
                "statusCode": 200,
                "responseBody": #"{"items":[{"id":1,"name":"Customer 1"}]}"#,
                "metadata": ["screen": "customers"]
            ]
        )
        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.reference"),
            object: nil,
            userInfo: [
                "owner": "CustomerListViewController",
                "target": "DeviceActuationService",
                "kind": "strong",
                "label": "fixture service reference",
                "metadata": ["screen": "customers"]
            ]
        )
        UserDefaults.standard.set(false, forKey: "new-nav")
        upsertLoupeKeychainFixture()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleItems.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ExampleCell.reuseIdentifier,
            for: indexPath
        ) as! ExampleCell
        cell.configure(item: visibleItems[indexPath.row])
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(
            DetailViewController(item: visibleItems[indexPath.row]),
            animated: true
        )
    }

    @objc private func openForm() {
        let controller = UINavigationController(rootViewController: FormViewController())
        controller.modalPresentationStyle = .formSheet
        present(controller, animated: true)
    }

    @objc private func openComponents() {
        navigationController?.pushViewController(ComponentsViewController(), animated: true)
    }

    @objc private func openFixtures() {
        navigationController?.pushViewController(FixtureTabController(), animated: true)
    }

    private func fixtureHeaderView() -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 68))
        header.accessibilityIdentifier = "example.fixtureHeader"

        let button = UIButton(type: .system)
        button.setTitle("Open Mixed Fixtures", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.backgroundColor = .secondarySystemFill
        button.layer.cornerRadius = 10
        button.accessibilityIdentifier = "example.openFixtures"
        button.addTarget(self, action: #selector(openFixtures), for: .touchUpInside)
        button.frame = CGRect(x: 20, y: 10, width: 362, height: 48)
        header.addSubview(button)

        return header
    }
}

extension ViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !query.isEmpty else {
            visibleItems = allItems
            tableView.reloadData()
            return
        }

        visibleItems = allItems.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
                || $0.status.localizedCaseInsensitiveContains(query)
        }
        tableView.reloadData()
    }
}

final class ExampleCell: UITableViewCell {
    static let reuseIdentifier = "ExampleCell"

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badgeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: ExampleItem) {
        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
        badgeLabel.text = item.status
        accessibilityIdentifier = "example.customer.\(item.index)"
        titleLabel.accessibilityIdentifier = "example.customer.\(item.index).title"
        subtitleLabel.accessibilityIdentifier = "example.customer.\(item.index).subtitle"
        badgeLabel.accessibilityIdentifier = "example.customer.\(item.index).status"
    }

    private func configure() {
        accessoryType = .disclosureIndicator

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        badgeLabel.font = .preferredFont(forTextStyle: .caption1)
        badgeLabel.textAlignment = .center
        badgeLabel.textColor = .label
        badgeLabel.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.16, alpha: 1)
                : UIColor(white: 0.92, alpha: 1)
        }
        badgeLabel.layer.cornerRadius = 6
        badgeLabel.layer.masksToBounds = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [textStack, badgeLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            badgeLabel.widthAnchor.constraint(equalToConstant: 58),
            badgeLabel.heightAnchor.constraint(equalToConstant: 26),
        ])
    }
}

final class DetailViewController: UIViewController {
    private let item: ExampleItem
    private let gestureCard = UIView()
    private let gestureStatus = UILabel()
    private var panOffset: CGFloat = 0

    init(item: ExampleItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = item.title
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "example.detail"
        configureLayout()
        configureGesture()
    }

    private func configureLayout() {
        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.accessibilityIdentifier = "example.detail.title"

        let subtitleLabel = UILabel()
        subtitleLabel.text = "\(item.subtitle) - \(item.status)"
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.accessibilityIdentifier = "example.detail.subtitle"

        gestureCard.backgroundColor = .systemIndigo
        gestureCard.layer.cornerRadius = 18
        gestureCard.accessibilityIdentifier = "example.gestureCard"

        let cardLabel = UILabel()
        cardLabel.text = "Swipe this card"
        cardLabel.textColor = .white
        cardLabel.font = .preferredFont(forTextStyle: .headline)
        cardLabel.textAlignment = .center
        cardLabel.translatesAutoresizingMaskIntoConstraints = false
        cardLabel.accessibilityIdentifier = "example.gestureCard.label"
        gestureCard.addSubview(cardLabel)

        gestureStatus.text = "Offset 0"
        gestureStatus.font = .preferredFont(forTextStyle: .body)
        gestureStatus.accessibilityIdentifier = "example.gestureStatus"

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, gestureCard, gestureStatus])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            gestureCard.heightAnchor.constraint(equalToConstant: 160),
            cardLabel.centerXAnchor.constraint(equalTo: gestureCard.centerXAnchor),
            cardLabel.centerYAnchor.constraint(equalTo: gestureCard.centerYAnchor),
        ])
    }

    private func configureGesture() {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gestureCard.addGestureRecognizer(recognizer)
        gestureCard.isUserInteractionEnabled = true
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        let nextOffset = panOffset + translation.x
        gestureCard.transform = CGAffineTransform(translationX: nextOffset, y: 0)
        gestureStatus.text = "Offset \(Int(nextOffset))"
        recognizer.setTranslation(.zero, in: view)

        if recognizer.state == .ended || recognizer.state == .cancelled {
            panOffset = nextOffset
        }
    }

}

final class BottomSheetFixtureViewController: UIViewController {
    private let sheetView = UIView()
    private let grabberButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let stateLabel = UILabel()
    private let expandedMarker = UILabel()
    private var topConstraint: NSLayoutConstraint?
    private var isExpanded = false

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Bottom Sheet"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "example.bottomSheet"
        configureBackdrop()
        configureSheet()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard !isExpanded else {
            return
        }
        topConstraint?.constant = collapsedTop
    }

    private var collapsedTop: CGFloat {
        max(view.bounds.height - 360, view.safeAreaInsets.top + 180)
    }

    private var expandedTop: CGFloat {
        view.safeAreaInsets.top + 16
    }

    private func configureBackdrop() {
        let mapLabel = UILabel()
        mapLabel.text = "Map Fixture"
        mapLabel.font = .preferredFont(forTextStyle: .largeTitle)
        mapLabel.textColor = .secondaryLabel
        mapLabel.textAlignment = .center
        mapLabel.translatesAutoresizingMaskIntoConstraints = false
        mapLabel.accessibilityIdentifier = "example.bottomSheet.backdrop"
        view.addSubview(mapLabel)

        NSLayoutConstraint.activate([
            mapLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 48),
        ])
    }

    private func configureSheet() {
        sheetView.backgroundColor = .secondarySystemBackground
        sheetView.layer.cornerRadius = 18
        sheetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetView.clipsToBounds = true
        sheetView.translatesAutoresizingMaskIntoConstraints = false
        sheetView.accessibilityIdentifier = "example.bottomSheet.sheet"
        view.addSubview(sheetView)

        grabberButton.setTitle("Card grabber", for: .normal)
        grabberButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        grabberButton.accessibilityIdentifier = "example.bottomSheet.grabber"
        grabberButton.accessibilityLabel = "Card grabber"
        grabberButton.addTarget(self, action: #selector(toggleSheet), for: .touchUpInside)

        stateLabel.text = "Collapsed"
        stateLabel.font = .preferredFont(forTextStyle: .headline)
        stateLabel.accessibilityIdentifier = "example.bottomSheet.state"

        expandedMarker.text = "Expanded"
        expandedMarker.font = .preferredFont(forTextStyle: .subheadline)
        expandedMarker.textColor = .systemGreen
        expandedMarker.isHidden = true
        expandedMarker.accessibilityIdentifier = "example.bottomSheet.expandedMarker"

        let headerStack = UIStackView(arrangedSubviews: [grabberButton, stateLabel, expandedMarker])
        headerStack.axis = .vertical
        headerStack.alignment = .center
        headerStack.spacing = 6

        scrollView.alwaysBounceVertical = true
        scrollView.accessibilityIdentifier = "example.bottomSheet.scrollView"

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        for index in 1...30 {
            let label = UILabel()
            label.text = "Place result \(index)"
            label.font = .preferredFont(forTextStyle: .body)
            label.backgroundColor = .tertiarySystemFill
            label.layer.cornerRadius = 8
            label.layer.masksToBounds = true
            label.accessibilityIdentifier = "example.bottomSheet.item.\(index)"
            contentStack.addArrangedSubview(label)
            label.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }

        let sheetStack = UIStackView(arrangedSubviews: [headerStack, scrollView])
        sheetStack.axis = .vertical
        sheetStack.spacing = 12
        sheetStack.translatesAutoresizingMaskIntoConstraints = false
        sheetView.addSubview(sheetStack)
        scrollView.addSubview(contentStack)

        let topConstraint = sheetView.topAnchor.constraint(equalTo: view.topAnchor, constant: collapsedTop)
        self.topConstraint = topConstraint

        NSLayoutConstraint.activate([
            topConstraint,
            sheetView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            grabberButton.heightAnchor.constraint(equalToConstant: 44),
            sheetStack.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor, constant: 20),
            sheetStack.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor, constant: -20),
            sheetStack.topAnchor.constraint(equalTo: sheetView.topAnchor, constant: 12),
            sheetStack.bottomAnchor.constraint(equalTo: sheetView.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    @objc private func toggleSheet() {
        setExpanded(!isExpanded)
    }

    private func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        topConstraint?.constant = expanded ? expandedTop : collapsedTop
        stateLabel.text = expanded ? "Expanded" : "Collapsed"
        expandedMarker.isHidden = !expanded
        view.layoutIfNeeded()
    }
}

final class ComponentsViewController: UIViewController {
    private let presentAlertAfterAppear: Bool
    private var didPresentInitialAlert = false
    private let scrollView = UIScrollView()
    private let symbolImageView = UIImageView()
    private let stateSwitch = UISwitch()
    private let volumeSlider = UISlider()
    private let stepper = UIStepper()
    private let segmentedControl = UISegmentedControl(items: ["Small", "Large"])
    private let datePicker = UIDatePicker()
    private let tabBar = UITabBar()
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 96, height: 56)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()
    private lazy var selfSizingCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.estimatedItemSize = CGSize(width: 96, height: 44)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()
    private let pickerView = UIPickerView()
    private let pageControl = UIPageControl()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let textField = UITextField()
    private let noteView = UITextView()
    private let alertButton = UIButton(type: .system)
    private let primaryButton = UIButton(type: .system)
    private let designCard = UIView()
    private let componentTiles = ["Label", "Image", "Control", "Input", "List"]
    private let selfSizingTiles = ["Short", "Adaptive title", "Wide"]
    private let pickerRows = ["North", "South", "West"]
    private var didSendLoupeComponentLog = false

    init(presentAlertAfterAppear: Bool = false) {
        self.presentAlertAfterAppear = presentAlertAfterAppear
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Components"
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Back",
            style: .plain,
            target: self,
            action: #selector(pop)
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "example.components.back"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(markDone)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "example.components.done"

        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "example.components"
        configureControls()
        layoutControls()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sendLoupeComponentLogIfNeeded()

        guard presentAlertAfterAppear, !didPresentInitialAlert else {
            return
        }
        didPresentInitialAlert = true
        showAlert()
    }

    private func sendLoupeComponentLogIfNeeded() {
        guard !didSendLoupeComponentLog else {
            return
        }
        didSendLoupeComponentLog = true
        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.log"),
            object: nil,
            userInfo: [
                "level": "info",
                "message": "example_components_visible",
                "metadata": ["screen": "components"]
            ]
        )
    }

    private func configureControls() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.accessibilityIdentifier = "example.components.scrollView"

        symbolImageView.image = UIImage(systemName: "checkmark.seal.fill")
        symbolImageView.tintColor = .systemGreen
        symbolImageView.contentMode = .scaleAspectFit
        symbolImageView.accessibilityIdentifier = "example.components.image"

        stateSwitch.isOn = true
        stateSwitch.accessibilityIdentifier = "example.components.switch"

        volumeSlider.minimumValue = 0
        volumeSlider.maximumValue = 100
        volumeSlider.value = 42
        volumeSlider.accessibilityIdentifier = "example.components.slider"

        stepper.minimumValue = 0
        stepper.maximumValue = 10
        stepper.stepValue = 2
        stepper.value = 4
        stepper.accessibilityIdentifier = "example.components.stepper"

        segmentedControl.selectedSegmentIndex = 1
        segmentedControl.accessibilityIdentifier = "example.components.segmented"

        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.date = Date(timeIntervalSince1970: 1_704_067_200)
        datePicker.accessibilityIdentifier = "example.components.datePicker"

        tabBar.items = [
            UITabBarItem(title: "Home", image: UIImage(systemName: "house"), tag: 0),
            UITabBarItem(title: "Search", image: UIImage(systemName: "magnifyingglass"), tag: 1),
        ]
        tabBar.selectedItem = tabBar.items?.first
        tabBar.accessibilityIdentifier = "example.components.tabBar"

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .secondarySystemBackground
        collectionView.layer.cornerRadius = 8
        collectionView.register(ComponentTileCell.self, forCellWithReuseIdentifier: ComponentTileCell.reuseIdentifier)
        collectionView.accessibilityIdentifier = "example.components.collectionView"

        selfSizingCollectionView.dataSource = self
        selfSizingCollectionView.delegate = self
        selfSizingCollectionView.backgroundColor = .secondarySystemBackground
        selfSizingCollectionView.layer.cornerRadius = 8
        selfSizingCollectionView.register(ComponentTileCell.self, forCellWithReuseIdentifier: ComponentTileCell.reuseIdentifier)
        selfSizingCollectionView.accessibilityIdentifier = "example.components.selfSizingCollectionView"

        pickerView.dataSource = self
        pickerView.delegate = self
        pickerView.selectRow(1, inComponent: 0, animated: false)
        pickerView.accessibilityIdentifier = "example.components.pickerView"

        pageControl.numberOfPages = 5
        pageControl.currentPage = 2
        pageControl.accessibilityIdentifier = "example.components.pageControl"

        progressView.progress = 0.65
        progressView.accessibilityIdentifier = "example.components.progress"

        activityIndicator.startAnimating()
        activityIndicator.accessibilityIdentifier = "example.components.activity"

        textField.placeholder = "Component text"
        textField.text = "Inspectable"
        textField.borderStyle = .roundedRect
        textField.accessibilityIdentifier = "example.components.textField"

        noteView.text = "Notes stay inspectable without bloating compact context."
        noteView.font = .preferredFont(forTextStyle: .body)
        noteView.layer.borderColor = UIColor.separator.cgColor
        noteView.layer.borderWidth = 1
        noteView.layer.cornerRadius = 8
        noteView.accessibilityIdentifier = "example.components.textView"

        alertButton.setTitle("Show Alert", for: .normal)
        alertButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        alertButton.backgroundColor = .secondarySystemFill
        alertButton.layer.cornerRadius = 10
        alertButton.accessibilityIdentifier = "example.components.alertButton"
        alertButton.addTarget(self, action: #selector(showAlert), for: .touchUpInside)

        primaryButton.setTitle("Primary Action", for: .normal)
        primaryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        primaryButton.backgroundColor = .systemBlue
        primaryButton.tintColor = .white
        primaryButton.layer.cornerRadius = 12
        primaryButton.accessibilityIdentifier = "example.components.button"
        primaryButton.addTarget(self, action: #selector(markDone), for: .touchUpInside)

        designCard.backgroundColor = .systemTeal
        designCard.layer.cornerRadius = 20
        designCard.layer.borderWidth = 2
        designCard.layer.borderColor = UIColor.systemMint.cgColor
        designCard.accessibilityIdentifier = "example.design.card"
    }

    private func layoutControls() {
        let label = UILabel()
        label.text = "UIKit Label"
        label.font = .preferredFont(forTextStyle: .headline)
        label.numberOfLines = 1
        label.accessibilityIdentifier = "example.components.label"

        let switchRow = row(title: "Enabled", control: stateSwitch, id: "example.components.switchRow")
        let sliderRow = row(title: "Volume", control: volumeSlider, id: "example.components.sliderRow")
        let stepperRow = row(title: "Stepper", control: stepper, id: "example.components.stepperRow")
        let dateRow = row(title: "Date", control: datePicker, id: "example.components.datePickerRow")
        let progressRow = row(title: "Progress", control: progressView, id: "example.components.progressRow")
        let activityRow = row(title: "Loading", control: activityIndicator, id: "example.components.activityRow")

        let designLabel = UILabel()
        designLabel.text = "Design fixture"
        designLabel.textColor = .white
        designLabel.font = .preferredFont(forTextStyle: .headline)
        designLabel.translatesAutoresizingMaskIntoConstraints = false
        designLabel.accessibilityIdentifier = "example.design.card.label"
        designCard.addSubview(designLabel)

        let stack = UIStackView(arrangedSubviews: [
            label,
            symbolImageView,
            switchRow,
            sliderRow,
            stepperRow,
            segmentedControl,
            alertButton,
            dateRow,
            tabBar,
            collectionView,
            selfSizingCollectionView,
            pickerView,
            pageControl,
            progressRow,
            activityRow,
            textField,
            noteView,
            primaryButton,
            designCard,
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
            symbolImageView.heightAnchor.constraint(equalToConstant: 36),
            tabBar.heightAnchor.constraint(equalToConstant: 52),
            collectionView.heightAnchor.constraint(equalToConstant: 72),
            selfSizingCollectionView.heightAnchor.constraint(equalToConstant: 72),
            pickerView.heightAnchor.constraint(equalToConstant: 120),
            noteView.heightAnchor.constraint(equalToConstant: 96),
            alertButton.heightAnchor.constraint(equalToConstant: 44),
            primaryButton.heightAnchor.constraint(equalToConstant: 48),
            designCard.heightAnchor.constraint(equalToConstant: 88),
            designLabel.centerXAnchor.constraint(equalTo: designCard.centerXAnchor),
            designLabel.centerYAnchor.constraint(equalTo: designCard.centerYAnchor),
        ])
    }

    private func row(title: String, control: UIView, id: String) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)

        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.accessibilityIdentifier = id
        if control === progressView {
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return row
    }

    @objc private func markDone() {
        primaryButton.setTitle("Done", for: .normal)
    }

    @objc private func showAlert() {
        let alert = UIAlertController(title: "UIKit Alert", message: "Inspectable alert fixture", preferredStyle: .alert)
        alert.view.accessibilityIdentifier = "example.components.alert"
        alert.addAction(UIAlertAction(title: "Close", style: .default))
        present(alert, animated: true)
    }

    @objc private func pop() {
        navigationController?.popViewController(animated: true)
    }
}

extension ComponentsViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === selfSizingCollectionView {
            return selfSizingTiles.count
        }
        return componentTiles.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ComponentTileCell.reuseIdentifier,
            for: indexPath
        ) as! ComponentTileCell
        if collectionView === selfSizingCollectionView {
            cell.configure(
                text: selfSizingTiles[indexPath.item],
                index: indexPath.item,
                idPrefix: "example.components.selfSizingCollection"
            )
        } else {
            cell.configure(text: componentTiles[indexPath.item], index: indexPath.item)
        }
        return cell
    }
}

extension ComponentsViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        pickerRows.count
    }

    func pickerView(
        _ pickerView: UIPickerView,
        titleForRow row: Int,
        forComponent component: Int
    ) -> String? {
        pickerRows[row]
    }
}

final class ComponentTileCell: UICollectionViewCell {
    static let reuseIdentifier = "ComponentTileCell"

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, index: Int, idPrefix: String = "example.components.collection") {
        titleLabel.text = text
        accessibilityIdentifier = "\(idPrefix).\(index)"
        titleLabel.accessibilityIdentifier = "\(idPrefix).\(index).label"
    }

    private func configure() {
        contentView.backgroundColor = .systemBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.separator.cgColor

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
}

final class FixtureTabController: UITabBarController {
    private let initialSelectedIndex: Int
    private let autoFocusKeyboard: Bool

    init(initialSelectedIndex: Int = 0, autoFocusKeyboard: Bool = false) {
        self.initialSelectedIndex = initialSelectedIndex
        self.autoFocusKeyboard = autoFocusKeyboard
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Fixtures"
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Back",
            style: .plain,
            target: self,
            action: #selector(pop)
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "example.fixtures.back"
        view.accessibilityIdentifier = "example.fixtures"
        tabBar.accessibilityIdentifier = "example.fixtures.tabBar"
        viewControllers = [
            fixtureController(SwiftUIFixtureController(), title: "SwiftUI", symbol: "sparkles", id: "swiftui", tag: 0),
            fixtureController(WebFixtureController(), title: "Web", symbol: "globe", id: "web", tag: 1),
            fixtureController(
                KeyboardFixtureController(autoFocusFirstField: autoFocusKeyboard),
                title: "Keyboard",
                symbol: "keyboard",
                id: "keyboard",
                tag: 2
            ),
            fixtureController(NestedScrollFixtureController(), title: "Nested", symbol: "rectangle.stack", id: "nested", tag: 3),
        ]
        selectedIndex = initialSelectedIndex
    }

    private func fixtureController(
        _ controller: UIViewController,
        title: String,
        symbol: String,
        id: String,
        tag: Int
    ) -> UIViewController {
        controller.title = title
        let tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), tag: tag)
        tabBarItem.accessibilityIdentifier = "example.fixtures.tab.\(id)"
        controller.tabBarItem = tabBarItem
        return controller
    }

    @objc private func pop() {
        navigationController?.popViewController(animated: true)
    }
}

struct SwiftUIFixtureView: View {
    @State private var enabled = true
    @State private var value = 0.35
    @State private var count = 2
    @State private var mode = "Focus"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SwiftUI Fixture")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("example.fixtures.swiftui.title")

            SwiftUIFixtureControls(
                enabled: $enabled,
                value: $value,
                count: $count,
                mode: $mode
            )

            Button(enabled ? "Disable" : "Enable") {
                enabled.toggle()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("example.fixtures.swiftui.button")

            SwiftUIFixtureRows()

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .accessibilityIdentifier("example.fixtures.swiftui")
        .localLoupeProbe("example.fixtures.swiftui.probe", label: "iOS SwiftUI probe")
    }
}

private struct SwiftUIFixtureControls: View {
    @Binding var enabled: Bool
    @Binding var value: Double
    @Binding var count: Int
    @Binding var mode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enabled", isOn: $enabled)
                .accessibilityIdentifier("example.fixtures.swiftui.toggle")

            Slider(value: $value)
                .accessibilityIdentifier("example.fixtures.swiftui.slider")

            Picker("Mode", selection: $mode) {
                Text("Focus").tag("Focus")
                Text("Review").tag("Review")
                Text("Ship").tag("Ship")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("example.fixtures.swiftui.mode")

            Stepper("Priority \(count)", value: $count, in: 1...5)
                .accessibilityIdentifier("example.fixtures.swiftui.stepper")

            ProgressView(value: value)
                .accessibilityIdentifier("example.fixtures.swiftui.progress")
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("example.fixtures.swiftui.controls")
        .localLoupeProbe("example.fixtures.swiftui.controls", label: "iOS SwiftUI controls")
    }
}

private struct SwiftUIFixtureRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(1...3, id: \.self) { index in
                HStack(spacing: 8) {
                    Image(systemName: index == 1 ? "checkmark.circle" : "circle")
                    Text("SwiftUI row \(index)")
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("example.fixtures.swiftui.row.\(index)")
                .localLoupeProbe(
                    "example.fixtures.swiftui.row.\(index)",
                    label: "iOS SwiftUI row \(index)"
                )
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("example.fixtures.swiftui.rows")
        .localLoupeProbe("example.fixtures.swiftui.rows", label: "iOS SwiftUI rows")
    }
}

private extension View {
    func localLoupeProbe(_ id: String, label: String? = nil) -> some View {
        modifier(LoupeLocalProbeModifier(id: id, label: label))
    }
}

private struct LoupeLocalProbeModifier: ViewModifier {
    let id: String
    let label: String?

    func body(content: Content) -> some View {
        content
            .background {
                LoupeFallbackProbeView(id: id, label: label)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            loupeRegisterRegionProbe(id, label: label, frame: proxy.frame(in: .global))
                        }
                        .onChange(of: proxy.frame(in: .global)) { frame in
                            loupeRegisterRegionProbe(id, label: label, frame: frame)
                        }
                }
            }
            .onDisappear {
                loupeRemoveProbe(id)
            }
    }

    private func loupeRegisterRegionProbe(_ id: String, label: String?, frame: CGRect) {
        guard frame.isFinite, !frame.isEmpty else {
            return
        }

        var userInfo: [String: Any] = [
            "id": id,
            "metadata": [
                "source": "local-region-probe",
                "loupe.swiftUI": true,
            ],
            "frame": [
                "x": Double(frame.origin.x),
                "y": Double(frame.origin.y),
                "width": Double(frame.width),
                "height": Double(frame.height),
            ],
        ]
        if let label {
            userInfo["label"] = label
        }

        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.probe"),
            object: nil,
            userInfo: userInfo
        )
    }

    private func loupeRemoveProbe(_ id: String) {
        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.removeProbe"),
            object: nil,
            userInfo: ["id": id]
        )
    }
}

private struct LoupeFallbackProbeView: UIViewRepresentable {
    let id: String
    let label: String?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.accessibilityIdentifier = id
        view.isAccessibilityElement = true
        view.accessibilityLabel = label ?? id
        view.backgroundColor = .clear
        publishSwiftUIMetadata(for: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.accessibilityIdentifier = id
        uiView.isAccessibilityElement = true
        uiView.accessibilityLabel = label ?? id
        uiView.backgroundColor = .clear
        publishSwiftUIMetadata(for: uiView)
    }

    private func publishSwiftUIMetadata(for view: UIView) {
        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.viewMetadata"),
            object: view,
            userInfo: [
                "metadata": [
                    "loupe.probe": true,
                    "loupe.swiftUI": true,
                ],
            ]
        )
    }
}

private extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
    }
}

final class SwiftUIFixtureController: UIHostingController<SwiftUIFixtureView> {
    init() {
        super.init(rootView: SwiftUIFixtureView())
        view.accessibilityIdentifier = "example.fixtures.swiftui.host"
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WebFixtureController: UIViewController {
    private let webView = WKWebView(frame: .zero)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "example.fixtures.web"
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.accessibilityIdentifier = "example.fixtures.web.webView"
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <style>
                body { font: -apple-system-body; margin: 24px; color: #111; background: #fff; }
                button { font: inherit; padding: 12px 16px; border-radius: 8px; border: 1px solid #999; }
              </style>
            </head>
            <body>
              <h1>Web Fixture</h1>
              <p id="status">Loaded inside WKWebView</p>
              <button aria-label="Web action">Action</button>
            </body>
            </html>
            """,
            baseURL: URL(string: "https://loupe.local/fixture")
        )
    }
}

final class KeyboardFixtureController: UIViewController {
    private let autoFocusFirstField: Bool
    private let firstNameField = UITextField()
    private let emailField = UITextField()
    private let codeField = UITextField()
    private let notesView = UITextView()
    private let resultLabel = UILabel()

    init(autoFocusFirstField: Bool = false) {
        self.autoFocusFirstField = autoFocusFirstField
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "example.fixtures.keyboard"
        configureControls()
        layoutControls()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if autoFocusFirstField {
            firstNameField.becomeFirstResponder()
        }
    }

    private func configureControls() {
        firstNameField.placeholder = "First name"
        firstNameField.borderStyle = .roundedRect
        firstNameField.textContentType = .givenName
        firstNameField.accessibilityIdentifier = "example.fixtures.keyboard.firstName"

        emailField.placeholder = "Email"
        emailField.borderStyle = .roundedRect
        emailField.keyboardType = .emailAddress
        emailField.textContentType = .emailAddress
        emailField.accessibilityIdentifier = "example.fixtures.keyboard.email"

        codeField.placeholder = "One time code"
        codeField.borderStyle = .roundedRect
        codeField.keyboardType = .numberPad
        codeField.textContentType = .oneTimeCode
        codeField.accessibilityIdentifier = "example.fixtures.keyboard.code"

        notesView.font = .preferredFont(forTextStyle: .body)
        notesView.layer.borderColor = UIColor.separator.cgColor
        notesView.layer.borderWidth = 1
        notesView.layer.cornerRadius = 8
        notesView.accessibilityIdentifier = "example.fixtures.keyboard.notes"

        resultLabel.text = "Waiting"
        resultLabel.font = .preferredFont(forTextStyle: .body)
        resultLabel.accessibilityIdentifier = "example.fixtures.keyboard.result"
    }

    private func layoutControls() {
        let saveButton = UIButton(type: .system)
        saveButton.setTitle("Save Keyboard Form", for: .normal)
        saveButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        saveButton.backgroundColor = .systemIndigo
        saveButton.tintColor = .white
        saveButton.layer.cornerRadius = 10
        saveButton.accessibilityIdentifier = "example.fixtures.keyboard.save"
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            firstNameField,
            emailField,
            codeField,
            notesView,
            saveButton,
            resultLabel,
        ])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            notesView.heightAnchor.constraint(equalToConstant: 120),
            saveButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    @objc private func save() {
        resultLabel.text = "Saved keyboard form"
    }
}

final class NestedScrollFixtureController: UIViewController {
    private let outerScrollView = UIScrollView()
    private let horizontalScrollView = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "example.fixtures.nested"
        layoutFixture()
    }

    private func layoutFixture() {
        outerScrollView.translatesAutoresizingMaskIntoConstraints = false
        outerScrollView.accessibilityIdentifier = "example.fixtures.nested.outerScroll"
        view.addSubview(outerScrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        outerScrollView.addSubview(stack)

        let header = UILabel()
        header.text = "Nested Scroll Fixture"
        header.font = .preferredFont(forTextStyle: .title2)
        header.accessibilityIdentifier = "example.fixtures.nested.title"
        stack.addArrangedSubview(header)

        horizontalScrollView.heightAnchor.constraint(equalToConstant: 112).isActive = true
        horizontalScrollView.accessibilityIdentifier = "example.fixtures.nested.horizontalScroll"
        stack.addArrangedSubview(horizontalScrollView)

        let horizontalStack = UIStackView()
        horizontalStack.axis = .horizontal
        horizontalStack.spacing = 12
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        horizontalScrollView.addSubview(horizontalStack)

        for index in 0..<8 {
            let tile = UILabel()
            tile.text = "Tile \(index + 1)"
            tile.textAlignment = .center
            tile.font = .preferredFont(forTextStyle: .headline)
            tile.backgroundColor = index.isMultiple(of: 2) ? .systemBlue : .systemGreen
            tile.textColor = .white
            tile.layer.cornerRadius = 10
            tile.layer.masksToBounds = true
            tile.accessibilityIdentifier = "example.fixtures.nested.tile.\(index)"
            horizontalStack.addArrangedSubview(tile)
            tile.widthAnchor.constraint(equalToConstant: 132).isActive = true
            tile.heightAnchor.constraint(equalToConstant: 96).isActive = true
        }

        for index in 0..<16 {
            let row = UILabel()
            row.text = "Nested row \(index + 1)"
            row.font = .preferredFont(forTextStyle: .body)
            row.backgroundColor = .secondarySystemBackground
            row.layer.cornerRadius = 8
            row.layer.masksToBounds = true
            row.accessibilityIdentifier = "example.fixtures.nested.row.\(index)"
            stack.addArrangedSubview(row)
            row.heightAnchor.constraint(equalToConstant: 48).isActive = true
        }

        NSLayoutConstraint.activate([
            outerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            outerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.widthAnchor, constant: -40),
            horizontalStack.leadingAnchor.constraint(equalTo: horizontalScrollView.contentLayoutGuide.leadingAnchor),
            horizontalStack.trailingAnchor.constraint(equalTo: horizontalScrollView.contentLayoutGuide.trailingAnchor),
            horizontalStack.topAnchor.constraint(equalTo: horizontalScrollView.contentLayoutGuide.topAnchor),
            horizontalStack.bottomAnchor.constraint(equalTo: horizontalScrollView.contentLayoutGuide.bottomAnchor),
            horizontalStack.heightAnchor.constraint(equalTo: horizontalScrollView.frameLayoutGuide.heightAnchor),
        ])
    }
}

final class FormViewController: UIViewController {
    private let nameField = UITextField()
    private let noteField = UITextView()
    private let saveButton = UIButton(type: .system)
    private let resultLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "New Record"
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "example.form"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(close)
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "example.form.cancel"

        configureControls()
        layoutControls()
    }

    private func configureControls() {
        nameField.placeholder = "Name"
        nameField.borderStyle = .roundedRect
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.accessibilityIdentifier = "example.form.name"

        noteField.font = .preferredFont(forTextStyle: .body)
        noteField.layer.borderColor = UIColor.separator.cgColor
        noteField.layer.borderWidth = 1
        noteField.layer.cornerRadius = 8
        noteField.accessibilityIdentifier = "example.form.note"

        saveButton.setTitle("Save", for: .normal)
        saveButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        saveButton.backgroundColor = .systemGreen
        saveButton.tintColor = .white
        saveButton.layer.cornerRadius = 12
        saveButton.accessibilityIdentifier = "example.form.save"
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)

        resultLabel.text = "Not saved"
        resultLabel.font = .preferredFont(forTextStyle: .body)
        resultLabel.accessibilityIdentifier = "example.form.result"
    }

    private func layoutControls() {
        let stack = UIStackView(arrangedSubviews: [nameField, noteField, saveButton, resultLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            noteField.heightAnchor.constraint(equalToConstant: 140),
            saveButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    @objc private func save() {
        let name = nameField.text?.isEmpty == false ? nameField.text! : "Untitled"
        resultLabel.text = "Saved \(name)"
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension FormViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

private func upsertLoupeKeychainFixture() {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.loupe.example",
        kSecAttrAccount as String: "fixture",
    ]
    let attributes: [String: Any] = [
        kSecValueData as String: Data("fixture-token".utf8),
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
        var item = query
        item[kSecValueData as String] = Data("fixture-token".utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

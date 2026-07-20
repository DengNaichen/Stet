import UIKit
import SwiftUI

class KeyboardViewController: UIInputViewController {

    override func updateViewConstraints() {
        super.updateViewConstraints()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let keyboardView = KeyboardView(
            onMicDown: { [weak self] in
                self?.openMainApp()
            },
            onMicUp: {
                // Mock behavior for the main app's internal preview
            },
            onBackspace: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            onReturn: { [weak self] in
                self?.textDocumentProxy.insertText("\n")
            },
            onNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            }
        )

        let hostingController = UIHostingController(rootView: keyboardView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.leftAnchor.constraint(equalTo: view.leftAnchor),
            hostingController.view.rightAnchor.constraint(equalTo: view.rightAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func openMainApp() {
        // 通过 URL Scheme 唤起主 App
        let url = URL(string: "stetmobile://dictate")!

        // UIInputViewController 跳转 URL 的特殊处理方式
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = responder?.next
        }

        // 备选方案（iOS 14+）
        extensionContext?.open(url, completionHandler: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkSharedData()
    }

    private func checkSharedData() {
        // 这里检测 App Group (UserDefaults) 中是否有主 App 识别完回传的文本
        // let sharedDefaults = UserDefaults(suiteName: "group.NaichengDeng.StetMobile")
        // if let text = sharedDefaults?.string(forKey: "last_recognized_text") {
        //     textDocumentProxy.insertText(text)
        //     sharedDefaults?.removeObject(forKey: "last_recognized_text")
        // }
    }
}

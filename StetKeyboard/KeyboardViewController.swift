//
//  KeyboardViewController.swift
//  StetKeyboard
//
//  Created by Naicheng Deng on 2026-04-30.
//

import UIKit
import SwiftUI

class KeyboardViewController: UIInputViewController {

    override func updateViewConstraints() {
        super.updateViewConstraints()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let keyboardView = KeyboardView(
            onMicTap: { [weak self] in
                self?.openMainApp()
            },
            onKeyTap: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
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
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    private func openMainApp() {
        guard let url = URL(string: "testvoice://dictate") else { return }
        extensionContext?.open(url)
    }

    override func textWillChange(_ textInput: UITextInput?) {
    }

    override func textDidChange(_ textInput: UITextInput?) {
    }
}

// File: BilingualDesk/Features/Import/ImportPreviewView.swift
// Targets: App
import SwiftUI

/// 页面二：导入预览（01 §4.2）。自身不含 NavigationStack，由呈现方包裹：
/// 书库用 sheet + NavigationStack，“Pending Imports” sheet 在自己的导航栈里推入它。
/// View 只读 ViewModel 的状态、调用 ViewModel 的方法（L1）。
struct ImportPreviewView: View {
    @StateObject private var viewModel: ImportPreviewViewModel
    private let onFinish: (ImportPreviewResult) -> Void

    init(candidate: ImportCandidate, importBook: ImportTXTBook, onFinish: @escaping (ImportPreviewResult) -> Void) {
        _viewModel = StateObject(wrappedValue: ImportPreviewViewModel(candidate: candidate, importBook: importBook))
        self.onFinish = onFinish
    }

    var body: some View {
        Form {
            titleSection
            fileSection
            splitSection
            switch viewModel.phase {
            case .parsing:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(AppText.T.importParsing)
                    }
                }
            case .parseFailed(let message):
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            case .ready, .saving:
                resultSection
                previewSection
            }
        }
        .disabled(viewModel.phase == .saving)
        .overlay {
            if viewModel.phase == .saving {
                savingOverlay
            }
        }
        .navigationTitle(AppText.T.importTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 在 “Pending Imports” sheet 里是推入的：隐藏系统返回按钮，左上只留 “Cancel”（01 §4.2），保存中也不能滑回。
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppText.T.commonCancel) {
                    viewModel.cancel()
                    onFinish(.cancelled)
                }
                .disabled(viewModel.phase == .saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(AppText.T.importConfirm) {
                    Task {
                        if let result = await viewModel.confirmImport() {
                            onFinish(result)
                        }
                    }
                }
                .disabled(!viewModel.canImport)
            }
        }
        .interactiveDismissDisabled(viewModel.phase == .saving)
        .task {
            // 第一次出现时开始解析；之后由切换分段规则触发重新解析。
            // 若页面消失时解析被取消、之后又出现（仍是 parsing 且没有结果），在这里重新开始。
            if viewModel.phase == .parsing && viewModel.preview == nil {
                viewModel.start()
            }
        }
        .onDisappear {
            // 下拉关闭或返回：取消正在进行的分段，不写入任何数据。
            viewModel.cancel()
        }
        .alert(
            AppText.T.importDuplicateTitle,
            isPresented: duplicateAlertBinding,
            presenting: viewModel.duplicateBook
        ) { book in
            Button(AppText.T.importDuplicateOpen) {
                onFinish(.duplicateOpenExisting(book))
            }
            Button(AppText.T.importDuplicateBack) {
                onFinish(.duplicateBackToLibrary(book))
            }
        } message: { book in
            Text(AppText.T.importDuplicateMessage(title: book.title))
        }
        .alert(
            viewModel.saveErrorMessage ?? "",
            isPresented: saveErrorAlertBinding
        ) {
            Button(AppText.T.commonOk) {}
        }
    }

    // MARK: - 区域

    private var titleSection: some View {
        Section {
            HStack {
                TextField(AppText.T.importTitlePlaceholder, text: $viewModel.title)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(AppText.T.importTitleCount(count: viewModel.titleCharacterCount))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(viewModel.titleCharacterCount > ImportLimits.maximumTitleLength ? Color.red : Color.secondary)
            }
        } header: {
            Text(AppText.T.importSectionTitle)
        } footer: {
            if let message = viewModel.titleErrorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }

    private var fileSection: some View {
        Section {
            Text(viewModel.fileSummary)
            if let encodingText = viewModel.encodingText {
                Text(encodingText)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(AppText.T.importSectionFile)
        }
    }

    private var splitSection: some View {
        Section {
            Picker(AppText.T.importSectionSplit, selection: splitRuleBinding) {
                ForEach(ParagraphSplitRule.allCases) { rule in
                    Text(rule.title).tag(rule)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(AppText.T.importSectionSplit)
        } footer: {
            Text(AppText.T.importSplitHint)
        }
    }

    private var resultSection: some View {
        Section {
            if let resultText = viewModel.resultText {
                Text(resultText)
            }
        } header: {
            Text(AppText.T.importSectionResult)
        }
    }

    private var previewSection: some View {
        Section {
            if let preview = viewModel.preview {
                ForEach(Array(preview.previewParagraphs.enumerated()), id: \.offset) { item in
                    Text(item.element)
                }
            }
        } header: {
            Text(AppText.T.importSectionPreview)
        } footer: {
            Text(AppText.T.importPreviewFootnote)
        }
    }

    private var savingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(AppText.T.importSaving)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 绑定

    private var splitRuleBinding: Binding<ParagraphSplitRule> {
        Binding(
            get: { viewModel.splitRule },
            set: { viewModel.changeSplitRule($0) }
        )
    }

    private var duplicateAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.duplicateBook != nil },
            set: { isPresented in
                if !isPresented && viewModel.duplicateBook != nil { viewModel.duplicateBook = nil }
            }
        )
    }

    private var saveErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented && viewModel.saveErrorMessage != nil { viewModel.saveErrorMessage = nil }
            }
        )
    }
}

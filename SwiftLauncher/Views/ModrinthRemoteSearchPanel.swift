import SwiftUI

struct ModrinthRemoteSearchPanel: View {
    @Bindable var store: LauncherStore
    let kind: ModrinthContentKind
    let instance: LauncherInstance
    @Binding var query: String
    @ViewState private var selectedFilters: [String: Set<String>] = [:]

    private var isCurrentContext: Bool {
        store.selectedDownloadContentKind == kind && store.selectedDownloadInstanceID == instance.id
    }

    private var isSearching: Bool {
        isCurrentContext && store.isSearchingMods
    }

    private var results: [ModrinthSearchResult] {
        isCurrentContext ? store.modrinthSearchResults : []
    }

    private var activeCategoryGroups: [[String]] {
        filterSections.compactMap { section in
            let values = selectedFilters[section.id, default: []]
            return values.isEmpty ? nil : Array(values).sorted()
        }
    }

    private var filterSections: [ModrinthFilterSection] {
        switch kind {
        case .mods:
            [
                .init(
                    title: "分类",
                    options: [
                        .init("冒险", "adventure"),
                        .init("Cursed", "cursed"),
                        .init("装饰", "decoration"),
                        .init("经济", "economy"),
                        .init("装备", "equipment"),
                        .init("食物", "food"),
                        .init("机制", "game-mechanics"),
                        .init("库", "library"),
                        .init("魔法", "magic"),
                        .init("管理", "management"),
                        .init("小游戏", "minigame"),
                        .init("生物", "mobs"),
                        .init("优化", "optimization"),
                        .init("社交", "social"),
                        .init("存储", "storage")
                    ]
                )
            ]
        case .resourcePacks:
            [
                .init(
                    title: "分类",
                    options: [
                        .init("combat", "combat"),
                        .init("cursed", "cursed"),
                        .init("decoration", "decoration"),
                        .init("modded", "modded"),
                        .init("realistic", "realistic"),
                        .init("simplistic", "simplistic"),
                        .init("themed", "themed"),
                        .init("tweaks", "tweaks"),
                        .init("utility", "utility"),
                        .init("vanilla-like", "vanilla-like")
                    ]
                ),
                .init(
                    title: "行为",
                    options: [
                        .init("audio", "audio"),
                        .init("blocks", "blocks"),
                        .init("core-shaders", "core-shaders"),
                        .init("entities", "entities"),
                        .init("environment", "environment"),
                        .init("equipment", "equipment"),
                        .init("fonts", "fonts"),
                        .init("gui", "gui"),
                        .init("items", "items"),
                        .init("locale", "locale"),
                        .init("models", "models")
                    ]
                ),
                .init(
                    title: "分辨率",
                    options: [
                        .init("8x-", "8x-"),
                        .init("16x", "16x"),
                        .init("32x", "32x"),
                        .init("48x", "48x"),
                        .init("64x", "64x"),
                        .init("128x", "128x"),
                        .init("256x", "256x"),
                        .init("512x+", "512x+")
                    ]
                )
            ]
        case .shaderPacks:
            [
                .init(
                    title: "分类",
                    options: [
                        .init("cartoon", "cartoon"),
                        .init("cursed", "cursed"),
                        .init("fantasy", "fantasy"),
                        .init("realistic", "realistic"),
                        .init("semi-realistic", "semi-realistic"),
                        .init("vanilla-like", "vanilla-like")
                    ]
                ),
                .init(
                    title: "加载器",
                    options: [
                        .init("canvas", "canvas"),
                        .init("iris", "iris"),
                        .init("optifine", "optifine"),
                        .init("vanilla", "vanilla")
                    ]
                ),
                .init(
                    title: "行为",
                    options: [
                        .init("atmosphere", "atmosphere"),
                        .init("bloom", "bloom"),
                        .init("colored-lighting", "colored-lighting"),
                        .init("foliage", "foliage"),
                        .init("path-tracing", "path-tracing"),
                        .init("pbr", "pbr"),
                        .init("reflections", "reflections"),
                        .init("shadows", "shadows")
                    ]
                ),
                .init(
                    title: "性能要求",
                    options: [
                        .init("high", "high"),
                        .init("low", "low"),
                        .init("medium", "medium"),
                        .init("potato", "potato"),
                        .init("screenshot", "screenshot")
                    ]
                )
            ]
        }
    }

    private var accentColor: Color {
        switch kind {
        case .mods: .green
        case .resourcePacks: .teal
        case .shaderPacks: .orange
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            filterSidebar
                .frame(width: 236)
                .background(.bar)

            Divider()

            resultsBody
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
        .searchable(text: $query, placement: .toolbar, prompt: "搜索资源")
        .onSubmit(of: .search) {
            Task { await search(loadIfEmptyOnly: false) }
        }
        .onChange(of: query) { oldValue, newValue in
            guard !oldValue.isEmpty && newValue.isEmpty else { return }
            Task { await search(loadIfEmptyOnly: false) }
        }
        .task(id: "\(kind.id)-\(instance.id)") {
            selectedFilters = [:]
            prepareContext(clearResults: true)
            await search(loadIfEmptyOnly: true)
        }
    }

    private var filterSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(filterSections) { section in
                    filterSection(section)
                }

                if !selectedFilters.isEmpty {
                    Button {
                        selectedFilters = [:]
                        Task { await search(loadIfEmptyOnly: false) }
                    } label: {
                        Label("清除筛选", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func filterSection(_ section: ModrinthFilterSection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(section.title)
                .font(.headline)
            FlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(section.options) { option in
                    filterChip(
                        option.title,
                        isSelected: selectedFilters[section.id, default: []].contains(option.category)
                    ) {
                        toggle(option, in: section)
                    }
                }
            }
        }
    }

    private func filterChip(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(
                isSelected ? accentColor.opacity(0.22) : Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? accentColor.opacity(0.65) : Color.secondary.opacity(0.15))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultsBody: some View {
        if !isCurrentContext || results.isEmpty && !isSearching {
            ContentUnavailableView {
                Label("没有\(kind.title)结果", systemImage: kind.systemImage)
            } description: {
                Text("可以换关键词，或清除筛选后再试。")
            } actions: {
                Button("查看热门\(kind.title)") {
                    query = ""
                    Task { await search(loadIfEmptyOnly: false) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { project in
                        resultRow(project)
                        Divider()
                            .padding(.leading, 88)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func resultRow(_ project: ModrinthSearchResult) -> some View {
        HStack(alignment: .center, spacing: 14) {
            RemoteImageIconView(
                url: project.iconURL,
                systemImage: kind.systemImage,
                tint: accentColor
            )
            .frame(width: 56, height: 56)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
            .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(project.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("by \(project.author)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(project.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !project.categories.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(project.categories.prefix(3), id: \.self) { category in
                            Text(category)
                                .font(.caption2.weight(.semibold))
                                .padding(.vertical, 2)
                                .padding(.horizontal, 5)
                                .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                        }
                        if project.categories.count > 3 {
                            Text("+\(project.categories.count - 3)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 7) {
                Label(project.downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
                Label(project.follows.formatted(.number.notation(.compactName)), systemImage: "heart")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 82, alignment: .trailing)

            Button("安装") {
                prepareContext(clearResults: false)
                Task {
                    await store.showModrinthDetails(kind, project, for: instance)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .frame(width: 72)
            .disabled(store.isWorking(on: instance) || store.isLoadingModDetails)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 18)
    }

    private func toggle(_ option: ModrinthFilterOption, in section: ModrinthFilterSection) {
        var values = selectedFilters[section.id, default: []]
        if values.contains(option.category) {
            values.remove(option.category)
        } else {
            values.insert(option.category)
        }
        if values.isEmpty {
            selectedFilters.removeValue(forKey: section.id)
        } else {
            selectedFilters[section.id] = values
        }
        Task { await search(loadIfEmptyOnly: false) }
    }

    private func search(loadIfEmptyOnly: Bool) async {
        prepareContext(clearResults: false)
        guard !loadIfEmptyOnly || results.isEmpty else { return }
        await store.searchModrinthContent(
            kind,
            query: query,
            categoryGroups: activeCategoryGroups,
            for: instance
        )
    }

    private func prepareContext(clearResults: Bool) {
        let contextChanged = store.selectedDownloadContentKind != kind || store.selectedDownloadInstanceID != instance.id
        guard contextChanged || clearResults else { return }
        store.selectedDownloadContentKind = kind
        store.selectedDownloadInstanceID = instance.id
        store.modInstallPlan = nil
        if clearResults || contextChanged {
            store.modrinthSearchResults = []
        }
    }
}

private struct ModrinthFilterSection: Identifiable {
    let title: String
    let options: [ModrinthFilterOption]

    var id: String { title }
}

private struct ModrinthFilterOption: Identifiable {
    let title: String
    let category: String

    var id: String { category }

    init(_ title: String, _ category: String) {
        self.title = title
        self.category = category
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.map(\.height).reduce(0, +) + max(CGFloat(rows.count - 1), 0) * lineSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(proposal: .init(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [FlowRow] = []
        var current = FlowRow()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if nextWidth > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = FlowRow()
            }
            current.append(subview: subview, size: size, spacing: spacing)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

private struct FlowRow {
    var items: [FlowItem] = []
    var width: CGFloat = 0
    var height: CGFloat = 0

    mutating func append(subview: LayoutSubview, size: CGSize, spacing: CGFloat) {
        width += items.isEmpty ? size.width : spacing + size.width
        height = max(height, size.height)
        items.append(FlowItem(subview: subview, size: size))
    }
}

private struct FlowItem {
    let subview: LayoutSubview
    let size: CGSize
}

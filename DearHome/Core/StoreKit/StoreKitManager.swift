import Foundation
import Observation
import StoreKit

/// Dear Home AI 会员档次，按订阅群组降序排列：
/// Max 为 Level 1（旗舰），Pro 为 Level 2（专业），Free 为免费兜底。
/// 对应 App Store Connect 中「Dear Home Membership」订阅群组内 Max 与 Pro 的层级顺序。
enum DearHomeTier: String, CaseIterable, Identifiable, Sendable {
    case max = "Max"
    case pro = "Pro"
    case free = "Free"

    var id: String { rawValue }

    /// 用于 entitlement 合并时的档位比较：数字越大，权益越高。
    var rank: Int {
        switch self {
        case .free: return 0
        case .pro: return 1
        case .max: return 2
        }
    }
}

/// 基于 StoreKit 2 的内购与自动续期订阅管理器。
///
/// - 拉取「Dear Home Membership」订阅群组中的商品（Max / Pro 的月付，以及可选年付）。
/// - 处理购买、恢复购买（Restore Purchases）与订阅状态监听（含退款/撤销后的自动回退）。
/// - 所有 UI 状态通过 `@Observable` 驱动，由 `AppModel.storeKit` 注入全局。
@MainActor
@Observable
final class StoreKitManager {
    // MARK: - Product IDs（订阅群组：Dear Home Membership）

    static let maxMonthlyID = "com.s2.dearhome.max.monthly"
    static let maxYearlyID = "com.s2.dearhome.max.yearly"
    static let proMonthlyID = "com.s2.dearhome.pro.monthly"
    static let proYearlyID = "com.s2.dearhome.pro.yearly"

    /// 本版核心上架的两个月付商品（Max 为 Level 1，Pro 为 Level 2）。
    static let coreProductIDs = [maxMonthlyID, proMonthlyID]

    /// 全量商品（含可选年付），统一请求、由 App Store 返回已配置项。
    static let allProductIDs = [maxMonthlyID, proMonthlyID, maxYearlyID, proYearlyID]

    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    // MARK: - Observable state

    var products: [Product] = []
    var activeTier: DearHomeTier = .free
    var loadState: LoadState = .idle
    var isPurchasing = false
    var purchaseError: Bilingual?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        startListening()
    }

    // MARK: - Convenience accessors

    var maxMonthly: Product? { product(id: Self.maxMonthlyID) }
    var proMonthly: Product? { product(id: Self.proMonthlyID) }
    var maxYearly: Product? { product(id: Self.maxYearlyID) }
    var proYearly: Product? { product(id: Self.proYearlyID) }

    func product(id: String) -> Product? {
        products.first { $0.id == id }
    }

    /// 月付商品按 Max(Level 1) → Pro(Level 2) 降序，年付排后。
    var monthlyProducts: [Product] {
        products
            .filter { Self.coreProductIDs.contains($0.id) }
            .sorted { tier(for: $0.id).rank > tier(for: $1.id).rank }
    }

    // MARK: - Load products

    func loadProducts() async {
        if case .ready = loadState { return }
        loadState = .loading
        purchaseError = nil
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            products = loaded.sorted { tier(for: $0.id).rank > tier(for: $1.id).rank }
            loadState = .ready
            await refreshEntitlements()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled:
                break
            case .pending:
                purchaseError = Bilingual(
                    en: "This purchase is pending approval.",
                    zh: "这笔购买正在等待批准。"
                )
            @unknown default:
                break
            }
        } catch {
            purchaseError = Bilingual(
                en: "Purchase failed: \(error.localizedDescription)",
                zh: "购买失败：\(error.localizedDescription)"
            )
        }
    }

    // MARK: - Restore purchases

    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = Bilingual(
                en: "Restore failed: \(error.localizedDescription)",
                zh: "恢复购买失败：\(error.localizedDescription)"
            )
        }
    }

    // MARK: - Entitlements

    /// 从当前有效交易中解析出最高档位（含退款/撤销后回退到更低档或 Free）。
    func refreshEntitlements() async {
        var highest = DearHomeTier.free
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            let tier = tier(for: transaction.productID)
            if tier.rank > highest.rank { highest = tier }
        }
        activeTier = highest
    }

    // MARK: - Private helpers

    private func startListening() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        do {
            let transaction = try checkVerified(transactionResult)
            await transaction.finish()
        } catch {
            // 未通过校验的交易不落账，但当前权益可能已变化（例如退款/撤销），刷新一次。
        }
        await refreshEntitlements()
    }

    private func tier(for productID: String) -> DearHomeTier {
        switch productID {
        case Self.maxMonthlyID, Self.maxYearlyID: return .max
        case Self.proMonthlyID, Self.proYearlyID: return .pro
        default: return .free
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }
}

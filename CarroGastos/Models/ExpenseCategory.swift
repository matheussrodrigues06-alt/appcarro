import SwiftUI

enum ExpenseCategory: String, CaseIterable, Identifiable, Codable {
    case fuel
    case maintenance
    case ipva
    case licensing
    case insurance
    case fine
    case fee
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fuel: "Abastecimento"
        case .maintenance: "Manutenção"
        case .ipva: "IPVA"
        case .licensing: "Licenciamento"
        case .insurance: "Seguro"
        case .fine: "Multa"
        case .fee: "Taxa"
        case .other: "Outros"
        }
    }

    var icon: String {
        switch self {
        case .fuel: "fuelpump.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .ipva: "doc.text.fill"
        case .licensing: "checkmark.seal.fill"
        case .insurance: "shield.fill"
        case .fine: "exclamationmark.triangle.fill"
        case .fee: "banknote.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var group: ExpenseGroup {
        switch self {
        case .fuel: .fuel
        case .maintenance: .maintenance
        case .ipva, .licensing, .insurance, .fee: .documents
        case .fine: .fines
        case .other: .other
        }
    }

    var color: Color { group.color }

    /// Categorias que aparecem na tela de Documentação.
    var isDocument: Bool {
        switch self {
        case .ipva, .licensing, .insurance, .fine, .fee: true
        default: false
        }
    }
}

/// Agrupamento usado no gráfico do Financeiro.
enum ExpenseGroup: String, CaseIterable, Identifiable {
    case maintenance = "Manutenção"
    case fuel = "Abastecimento"
    case documents = "Documentação"
    case fines = "Multas"
    case other = "Outros"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .maintenance: Color.serviceViolet
        case .fuel: Color.fuelBlue
        case .documents: Color.docsTeal
        case .fines: Color.danger
        case .other: Color.gray
        }
    }
}

/// Situação de um vencimento.
enum DueStatus: Int, Comparable {
    case ok = 0
    case soon = 1
    case overdue = 2

    static func < (lhs: DueStatus, rhs: DueStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    var color: Color {
        switch self {
        case .ok: Color.success
        case .soon: Color.warning
        case .overdue: Color.danger
        }
    }

    var title: String {
        switch self {
        case .ok: "Em dia"
        case .soon: "Atenção"
        case .overdue: "Vencido"
        }
    }

    var icon: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .soon: "clock.fill"
        case .overdue: "exclamationmark.circle.fill"
        }
    }
}

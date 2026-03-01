import Foundation
import SwiftData

@Model
final class PersonInterest {
    var personNumber: Int
    var interestName: String
    var interestTypeText: String?
    var functionInAgencyText: String?
    var paid: Bool?
    var organizationTypeText: String?

    var parlamentarier: Parlamentarier?

    init(
        personNumber: Int,
        interestName: String,
        interestTypeText: String?,
        functionInAgencyText: String?,
        paid: Bool?,
        organizationTypeText: String?,
        parlamentarier: Parlamentarier? = nil
    ) {
        self.personNumber = personNumber
        self.interestName = interestName
        self.interestTypeText = interestTypeText
        self.functionInAgencyText = functionInAgencyText
        self.paid = paid
        self.organizationTypeText = organizationTypeText
        self.parlamentarier = parlamentarier
    }
}

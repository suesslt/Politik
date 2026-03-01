import Foundation
import SwiftData

@Model
final class PersonOccupation {
    var personNumber: Int
    var occupationName: String
    var employer: String?
    var jobTitle: String?

    var parlamentarier: Parlamentarier?

    init(
        personNumber: Int,
        occupationName: String,
        employer: String?,
        jobTitle: String?,
        parlamentarier: Parlamentarier? = nil
    ) {
        self.personNumber = personNumber
        self.occupationName = occupationName
        self.employer = employer
        self.jobTitle = jobTitle
        self.parlamentarier = parlamentarier
    }
}

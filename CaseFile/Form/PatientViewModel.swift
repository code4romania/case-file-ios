//
//  AddPatientViewModel.swift
//  CaseFile
//
//  Created by Andrei Bouariu on 15/06/2020.
//  Copyright © 2020 Code4Ro. All rights reserved.
//

import UIKit

typealias ClosureTypeAnyArray = ([Any]?) -> Void

class PatientForm: CustomStringConvertible {
    
    enum FormFieldType {
        case name
        case birthDate
        case civilStatus
        case county
        case city
        case gender
        case relationship
    }
    
    // the text above the field
    var text: String
    
    // the placeholder inside the field
    var placeholder: String
    
    // the type of field
    var fieldType: FormFieldType
    
    // the value of the field (from text field, drop down, date selector etc)
    var value: Any?
    
    var description: String {
        if let value = value as? Date {
            return timeFormatter.string(from: value)
        }
        if let value = value as? String {
            return value
        }
        if let value = value as? CustomStringConvertible {
            return value.description
        }
        return ""
    }
    
    // the data source to choose for dropdowns
    var getSource: ((ClosureTypeAnyArray?) -> ())?
    
    var isLoading = false
    
    lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()
    
    init(_ text: String,
         _ placeholder: String,
         _ fieldType: FormFieldType,
         _ value: CustomStringConvertible?,
         _ getSource: ((ClosureTypeAnyArray?) -> ())?) {
        self.text = text
        self.placeholder = placeholder
        self.fieldType = fieldType
        self.value = value
        self.getSource = getSource
    }
}

enum PatientViewModelOperation {
    case add
    case edit
    case view
}

class PatientViewModel: NSObject {
    
    /// This specifies if the view model is to view, add or edit benficiary
    var operation: PatientViewModelOperation
    
    /// Current beneficiary
    var beneficiary: Beneficiary? {
        didSet {
            if let beneficiary = beneficiary {
                let object: NSArray = [beneficiary]
                ApplicationData.shared.setObject(object, for: .patient)
            } else {
                ApplicationData.shared.removeObject(for: .patient)
            }
        }
    }
    
    var isFamilyOfBeneficiary: Beneficiary? {
        didSet {
            if let isFamilyOfBeneficiary = isFamilyOfBeneficiary {
                let object: NSArray = [isFamilyOfBeneficiary]
                ApplicationData.shared.setObject(object, for: .patientFamilyMember)
            } else {
                ApplicationData.shared.removeObject(for: .patientFamilyMember)
            }
        }
    }

    /// If the beneficiary is set, decides whether the beneficiary name will be displayed in the header or not
    var shouldOverrideHeaderContent = true
    
    /// List of beneficiaries
    var beneficiaryList: [Beneficiary]? {
        DB.shared.currentUser()?.beneficiaries?
            .compactMap({ $0 as? Beneficiary })
            .sorted(by: { $0.id > $1.id })
    }
    
    // List of completed forms
    var filledForms: [FormSummaryCellModel]? {
        guard let beneficiary = beneficiary,
            let forms = beneficiary.forms?.allObjects as? [Form] else {
                return []
        }
        var filledForms = [FormSummaryCellModel]()
        for form in forms {
            let answeredQuestions = DB.shared.getAnsweredQuestions(inFormWithId: Int(form.id),
                                                                   beneficiary: beneficiary).count
            let answers = DB.shared.getAnswers(inFormWithId: Int(form.id),
                                               beneficiary: beneficiary)
            let formSections = LocalStorage.shared.loadForm(withId: Int(form.id))
            let totalQuestions = formSections?.reduce([QuestionResponse](), { $0 + $1.questions }).count ?? 0
            if let firstAnswer = answers.first,
                answeredQuestions == totalQuestions {
                let synced = answers.filter({ $0.synced }).count == answers.count
                filledForms.append(FormSummaryCellModel(synced: synced,
                                                        fillDate: firstAnswer.fillDate,
                                                        name: form.formDescription,
                                                        formId: Int(form.id)))
            }
        }
        return filledForms
    }
    
    var notesModel: NoteViewModel?
    
    /// Be notified when the API save state has changed
    var onSaveStateChanged: (() -> Void)?
    
    /// Be notified whenever the model data changes so you can update the interface with fresh data
    var onStateChanged: (() -> Void)?
    
    /// Be notified when a form is filled
    var onFormFilled: (() -> Void)?
    
    var canContinue: Bool {
        return self.generalDataSource.allSatisfy { $0.value != nil }
    }
    
    fileprivate(set) var isSaving: Bool = false {
        didSet {
            onSaveStateChanged?()
        }
    }
    
    fileprivate(set) var availableCounties: [CountyResponse] = LocalStorage.shared.getCounties() ?? [] {
        didSet {
            onStateChanged?()
        }
    }
    fileprivate(set) var availableCities: [CityResponse] = [] {
        didSet {
            onStateChanged?()
        }
    }
    
    // MARK: Add/edit form properties
    var _nameForm: PatientForm?
    var nameForm: PatientForm {
        if _nameForm == nil {
            _nameForm = PatientForm("Patients.Add.Field.Name.Title".localized,
                                    "Patients.Add.Field.Name.Description".localized,
                                    .name,
                                    beneficiary?.name,
                                    nil)
        }
        return _nameForm!
    }
    
    var _birthForm: PatientForm?
    var birthForm: PatientForm {
        if _birthForm == nil {
            _birthForm = PatientForm("Patients.Add.Field.Date.Title".localized,
                                     "Patients.Add.Field.Date.Description".localized,
                                     .birthDate,
                                     beneficiary?.birthDate,
                                     nil)
        }
        return _birthForm!
    }
    
    var _civilStatusForm: PatientForm?
    var civilStatusForm: PatientForm {
        if _civilStatusForm == nil {
            _civilStatusForm = PatientForm("Patients.Add.Field.CivilStatus.Title".localized,
                                           "Patients.Add.Field.CivilStatus.Description".localized,
                                           .civilStatus,
                                           { [weak self] in
                                            guard let beneficiary = self?.beneficiary else {
                                                return nil
                                            }
                                            return CivilStatus(rawValue: Int(beneficiary.civilStatus))
                                            }(),
                                           { populateCivilStatuses in
                                            populateCivilStatuses?([CivilStatus.notMarried,
                                                                    CivilStatus.married,
                                                                    CivilStatus.divorced,
                                                                    CivilStatus.widowed])
            })
        }
        return _civilStatusForm!
    }
    
    var _countyForm: PatientForm?
    var countyForm: PatientForm {
        if _countyForm == nil {
            let populateCountiesClosure: (ClosureTypeAnyArray?) -> () =
            { [weak self] populateCounties in
                guard let self = self else {
                    return
                }
                self.updateSource(for: self.countyForm) { [weak self] error in
                    guard let self = self else {
                        return
                    }
                    populateCounties?(self.availableCounties)
                }
            }
            _countyForm = PatientForm("Patients.Add.Field.County.Title".localized,
                                      "Patients.Add.Field.County.Description".localized,
                                      .county,
                                      { [weak self] in
                                        guard let beneficiary = self?.beneficiary,
                                            let county = beneficiary.county else {
                                                return nil
                                        }
                                        return CountyResponse(id: Int(beneficiary.countyId),
                                                              name: county,
                                                              code: "")
                                        }(),
                                      populateCountiesClosure)
        }
        return _countyForm!
    }
    
    var _cityForm: PatientForm?
    var cityForm: PatientForm {
        if _cityForm == nil {
            let populateCitiesClosure: (ClosureTypeAnyArray?) -> () =
            { [weak self] populateCities in
                guard let self = self else {
                    return
                }
                self.updateSource(for: self.cityForm) { [weak self] error in
                    guard let self = self else {
                        return
                    }
                    populateCities?(self.availableCities)
                }
            }
            _cityForm = PatientForm("Patients.Add.Field.City.Title".localized,
                                    "Patients.Add.Field.City.Description".localized,
                                    .city,
                                    { [weak self] in
                                        guard let beneficiary = self?.beneficiary,
                                            let city = beneficiary.city else {
                                                return nil
                                        }
                                        return CityResponse(id: Int(beneficiary.cityId),
                                                            name: city)
                                        }(),
                                    populateCitiesClosure)
        }
        return _cityForm!
    }
    
    var _genderForm: PatientForm?
    var genderForm: PatientForm {
        if _genderForm == nil {
            _genderForm = PatientForm("Patients.Add.Field.Gender.Title".localized,
                                      "Patients.Add.Field.Gender.Description".localized,
                                      .gender,
                                      { [weak self] in
                                        guard let beneficiary = self?.beneficiary else {
                                            return nil
                                        }
                                        return Gender(rawValue: Int(beneficiary.gender))
                                        }(),
                                      { populateGenders in
                                        populateGenders?([Gender.male, Gender.female])
            })
        }
        return _genderForm!
    }
    
    var generalDataSource: [PatientForm] = []
    
    init(operation: PatientViewModelOperation) {
        self.operation = operation
        super.init()
        self.resetForm()
    }
    
    // MARK: Form operations
    func updateSource(for form: PatientForm, completion: @escaping (APIError?) -> ()) {
        switch form.fieldType {
        case .county:
            form.isLoading = true
            onStateChanged?()
            self.fetchCounties { [weak self] (error) in
                form.isLoading = false
                self?.onStateChanged?()
                completion(error)
            }
        case .city:
            guard let countyValue = countyForm.value as? CountyResponse else {
                completion(.generic(reason: "Validation.CountyNotSelected".localized))
                return
            }
            form.isLoading = true
            onStateChanged?()
            self.fetchCities(countyId: countyValue.id) { [weak self] (error) in
                form.isLoading = false
                self?.onStateChanged?()
                completion(error)
            }
        default:
            break
        }
    }
    
    func fetchCounties(then completion: ((APIError?) -> ())?) {
        // Attempt to retrieve counties from Local storage, otherwise API call
        if let cachedCounties = LocalStorage.shared.getCounties() {
            self.availableCounties = cachedCounties
            self.availableCities = []
            completion?(nil)
            return
        }
        AppDelegate.dataSourceManager.fetchCounties(completion: { (counties, error) in
            if let counties = counties {
                self.availableCounties = counties
                self.availableCities = []
                LocalStorage.shared.setCounties(counties)
            }
            completion?(error)
        })
    }
    
    func fetchCities(countyId: Int, then completion: ((APIError?) -> ())?) {
        // Attempt to retrieve cities from Local storage, otherwise API call
        if let cachedCities = LocalStorage.shared.getCities(countyId: countyId) {
            self.availableCities = cachedCities
            completion?(nil)
            return
        }
        AppDelegate.dataSourceManager.fetchCities(countyId: countyId, completion: { (cities, error) in
            if let cities = cities {
                self.availableCities = cities
                LocalStorage.shared.setCities(cities, for: countyId)
            }
            completion?(error)
        })
    }
    
    func processForm() {
        if beneficiary == nil {
            beneficiary = DB.shared.createBeneficiary(persistent: false)
        }
        beneficiary!.name = nameForm.value as? String
        beneficiary!.birthDate = birthForm.value as? Date
        beneficiary!.civilStatus = Int16((civilStatusForm.value as! CivilStatus).rawValue)
        beneficiary!.cityId = Int16((cityForm.value as! CityResponse).id)
        beneficiary!.city = (cityForm.value as! CityResponse).name
        beneficiary!.countyId = Int16((countyForm.value as! CountyResponse).id)
        beneficiary!.county = (countyForm.value as! CountyResponse).name
        beneficiary!.gender = Int16((genderForm.value as! Gender).rawValue)
        beneficiary!.user = DB.shared.currentUser()
        if let familyMember = ApplicationData.shared.beneficiaryFamilyMember {
            if let extendedFamilyMembers = familyMember.familyMembers {
                beneficiary!.addToFamilyMembers(extendedFamilyMembers)
            }
            beneficiary!.addToFamilyMembers(familyMember)
        }
    }
    
    func resetForm() {
        _nameForm = nil
        _birthForm = nil
        _civilStatusForm = nil
        _countyForm = nil
        _cityForm = nil
        _genderForm = nil
        isFamilyOfBeneficiary = nil
        generalDataSource = [
            nameForm,
            birthForm,
            civilStatusForm,
            countyForm,
            cityForm,
            genderForm
        ]
    }
    
    func rollback() {
        CoreData.context.rollback()
    }
    
    deinit {
//        print("DEINIT PATIENT VIEW MODEL")
//        if let isFamilyOfBeneficiary = isFamilyOfBeneficiary {
//            beneficiary = isFamilyOfBeneficiary
//        }
    }
    
}

extension PatientViewModel {
    // creates the beneficiary and their assigned forms on server
    static func createBeneficiary(completion:((Int?, APIError?) -> Void)?) {
        guard let beneficiary = ApplicationData.shared.beneficiary,
            let formsArray = ApplicationData.shared.object(for: ApplicationData.Keys.patientForms) as? NSArray,
            let formsRemoved = ApplicationData.shared.object(for: ApplicationData.Keys.patientRemovedForms) as? NSArray,
            let formsAdded = ApplicationData.shared.object(for: ApplicationData.Keys.patientAddedForms) as? NSArray
            else {
                completion?(nil, .incorrectFormat(reason: "Error_Unknown".localized))
                return
        }
        
        let isNew = beneficiary.id == -1
        let selectedForms = isNew ? formsArray
            .compactMap({ $0 as? FormSetCellModel })
            .map({ $0.id }) : nil
        let addedForms = isNew ? [] : formsAdded
            .compactMap({ $0 as? FormSetCellModel })
            .map({ $0.id })
        let removedForms = isNew ? [] : formsRemoved
            .compactMap({ $0 as? FormSetCellModel })
            .map({ $0.id })
        let familyMemberIdInt16 = ApplicationData.shared.beneficiaryFamilyMember?.id
        let familyMemberId = familyMemberIdInt16 != nil ? Int(familyMemberIdInt16!) : nil
        let beneficiaryRequest = BeneficiaryRequest(id: beneficiary.id,
                                                    userId: beneficiary.userId,
                                                    name: beneficiary.name,
                                                    birthDate: beneficiary.birthDate,
                                                    civilStatus: CivilStatus(rawValue: Int(beneficiary.civilStatus))!,
                                                    cityId: beneficiary.cityId,
                                                    countyId: beneficiary.countyId,
                                                    gender: Gender(rawValue: Int(beneficiary.gender))!,
                                                    formsIds: selectedForms,
                                                    newAllocatedFormsIds: addedForms,
                                                    dealocatedFormsIds: removedForms,
                                                    isFamilyOfBeneficiaryId: familyMemberId)
        AppDelegate.dataSourceManager.createOrUpdateBeneficiary(beneficiaryRequest, isNew: isNew) { (beneficiaryId, error) in
            guard error == nil, let beneficiaryId = beneficiaryId else {
                completion?(nil, error)
                return
            }
            if isNew {
                beneficiary.id = Int16(beneficiaryId)
                beneficiary.age = Int16(beneficiary.birthDate?.currentAge ?? -1)
                DB.shared.assignFormsToBeneficiary(beneficiary, formIds: selectedForms!)
            } else {
                beneficiary.age = Int16(beneficiary.birthDate?.currentAge ?? -1)
                DB.shared.assignFormsToBeneficiary(beneficiary, formIds: addedForms)
                DB.shared.unassignFormsFromBeneficiary(beneficiary, formIds: removedForms)
            }
            CoreData.saveContext()
            completion?(beneficiaryId, error)
        }
    }
}

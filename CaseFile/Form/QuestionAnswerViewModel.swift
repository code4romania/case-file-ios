//
//  QuestionAnswerViewModel.swift
//  MonitorizareVot
//
//  Created by Cristi Habliuc on 28/10/2019.
//  Copyright © 2019 Code4Ro. All rights reserved.
//

import UIKit
import CoreData

struct QuestionAnswerCellModel {
    
    struct AnswerModel {
        var optionId: Int
        var isFreeText: Bool
        var text: String?
        var userText: String? = nil
        var isSelected: Bool

        mutating func setIsSelected(_ selected: Bool) { isSelected = selected }
        mutating func setUserText(_ text: String?) { self.userText = text }
    }
    
    var questionId: Int
    var questionCode: String
    var questionText: String
    var type: QuestionResponse.QuestionType
    var acceptsMultipleAnswers: Bool
    var questionAnswers: [AnswerModel]
    var isNoteAttached: Bool
    var isSaved: Bool
    var isSynced: Bool
    var isMandatory: Bool
    
    mutating func setIsNoteAttached(_ attached: Bool) { isNoteAttached = attached }
    mutating func setIsSaved(_ isSaved: Bool) { self.isSaved = isSaved }
    mutating func setIsSynced(_ isSynced: Bool) { self.isSynced = isSynced }
    mutating func setSelectedAnswer(atIndex index: Int) {
        for i in 0..<questionAnswers.count {
            questionAnswers[i].isSelected = i == index
        }
    }
}

class QuestionAnswerViewModel: NSObject {
    fileprivate var form: FormResponse
    fileprivate var sections: [FormSectionResponse]
    
    var questions: [QuestionAnswerCellModel] = []
    fileprivate(set) var currentQuestionIndex: Int = 0
    
    /// Bind to this callback to be notified whenever the model data is updated
    var onModelUpdate: (() -> Void)?
    
    init?(withFormUsingId id: Int, currentQuestionId: Int) {
        guard let form = LocalStorage.shared.getFormSummary(withId: id),
            let sections = LocalStorage.shared.loadForm(withId: form.id) else { return nil }
        self.form = form
        self.sections = sections
        super.init()
        
        // initialize the models
        generateModels(usingFormSections: sections)
        setCurrentIndex(withQuestionId: currentQuestionId)
    }
    
    fileprivate func generateModels(usingFormSections formSections: [FormSectionResponse]) {
        let allQuestions = formSections.reduce(into: [QuestionResponse]()) { $0 += $1.questions }
        
        var models: [QuestionAnswerCellModel] = []
        for questionMeta in allQuestions {
            let question = DB.shared.getQuestion(withId: questionMeta.id)
            
            // Logic is based on the first answer found for the form and beneficiary. We assume that all other answers for the same form and beneficiary have the same synchronization status since they're performed in the same API call.
            var firstAnswer: Answer?
            if let beneficiary = ApplicationData.shared.beneficiary,
            question?.answers != nil {
                let answeredByBeneficiaryPredicate = NSPredicate(format: "beneficiary = %@", beneficiary)
                firstAnswer = question!.answers!.filtered(using: answeredByBeneficiaryPredicate).first as? Answer
            }
            let options = questionMeta.options

            let acceptsMultipleAnswers = [
                QuestionResponse.QuestionType.multipleAnswers,
                QuestionResponse.QuestionType.multipleAnswerWithText]
                .contains(questionMeta.questionType)

            let storedAnswers = question?.answers?.allObjects as? [Answer] ?? []
            let mappedAnswers = storedAnswers
                .filter({ $0.beneficiary != nil && $0.beneficiary == ApplicationData.shared.beneficiary })
                .reduce(into: [Int: Answer]()) { $0[Int($1.id)] = $1 }
            
            let isNoteAttached = question?.note != nil

            var answerModels: [QuestionAnswerCellModel.AnswerModel] = []
            for optionMeta in options {
                let answer = mappedAnswers[optionMeta.id]
                var model = QuestionAnswerCellModel.AnswerModel(
                    optionId: optionMeta.id,
                    isFreeText: optionMeta.isFreeText,
                    text: optionMeta.text.count > 0 ? optionMeta.text : "Other".localized,
                    isSelected: answer?.selected == true)
                model.setUserText(answer?.inputText)
                answerModels.append(model)
            }
            
            let model = QuestionAnswerCellModel(
                questionId: questionMeta.id,
                questionCode: questionMeta.code,
                questionText: questionMeta.text,
                type: questionMeta.questionType,
                acceptsMultipleAnswers: acceptsMultipleAnswers,
                questionAnswers: answerModels,
                isNoteAttached: isNoteAttached,
                isSaved: firstAnswer != nil,
                isSynced: firstAnswer?.synced == true,
                isMandatory: questionMeta.isMandatory)
            models.append(model)
        }
        self.questions = models
    }
    
    fileprivate func setCurrentIndex(withQuestionId questionId: Int) {
        currentQuestionIndex = questions.firstIndex(where: { $0.questionId == questionId }) ?? 0
    }
    
    func updateSelection(ofQuestion questionModel: QuestionAnswerCellModel,
                         answerIndex: Int) {
        guard let questionIndex = questionIndex(withModel: questionModel) else { return }
        
        let questionData = questions[questionIndex]
        let answerData = questionData.questionAnswers[answerIndex]
        
        if questionData.acceptsMultipleAnswers {
            questions[questionIndex].questionAnswers[answerIndex].setIsSelected(!answerData.isSelected)
        } else {
            for i in 0..<questionData.questionAnswers.count {
                let isAlreadySelected = questions[questionIndex].questionAnswers[i].isSelected
                questions[questionIndex].questionAnswers[i].setIsSelected(!isAlreadySelected && i == answerIndex)
            }
        }
        
        save(withModel: questions[questionIndex])
        questions[questionIndex].isSaved = true
        questions[questionIndex].isSynced = false
        
        MVAnalytics.shared.log(event: .answerQuestion(code: questionData.questionCode))
        
        RemoteSyncer.shared.syncUnsyncedData { error in
            self.generateModels(usingFormSections: self.sections)
            self.onModelUpdate?()
        }
    }
    
    func updateUserText(ofQuestion questionModel: QuestionAnswerCellModel,
                        answerIndex: Int,
                        userText: String?) {
        guard let questionIndex = questionIndex(withModel: questionModel) else { return }
        let normalizedText = userText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text = normalizedText, text.count > 0 else { return }
        let questionData = questions[questionIndex]
        questions[questionIndex].questionAnswers[answerIndex].userText = text
        let isSelected = text.count > 0
        questions[questionIndex].questionAnswers[answerIndex].setIsSelected(isSelected)
        if isSelected && !questionData.acceptsMultipleAnswers {
            // deselect other options
            for i in 0..<questions[questionIndex].questionAnswers.count {
                questions[questionIndex].questionAnswers[i].setIsSelected(i == answerIndex)
            }
        }
        
        save(withModel: questions[questionIndex])
        questions[questionIndex].isSaved = true
        questions[questionIndex].isSynced = false
        
        MVAnalytics.shared.log(event: .answerQuestion(code: questionData.questionCode))

        RemoteSyncer.shared.syncUnsyncedData { error in
            self.generateModels(usingFormSections: self.sections)
            self.onModelUpdate?()
        }
    }
    
    func questionIndex(withModel questionModel: QuestionAnswerCellModel) -> Int? {
        return questions.firstIndex(where: { $0.questionId == questionModel.questionId })
    }
    
    func save(withModel questionModel: QuestionAnswerCellModel) {
        
        guard let currentBeneficiary = ApplicationData.shared.beneficiary else {
            return
        }
                
        var question: Question! = DB.shared.getQuestion(withId: questionModel.questionId)
        if question == nil {
            question = NSEntityDescription.insertNewObject(forEntityName: "Question", into: CoreData.context) as? Question
            question.formId = Int16(form.id)
            question.formVersion = Int16(form.version)
            question.id = Int16(questionModel.questionId)
            question.type = Int16(questionModel.type.rawValue)
            if let sectionId = sections
                .filter({ $0.questions
                    .map({ $0.id })
                    .contains(questionModel.questionId) })
                .first?.sectionId {
                question.sectionInfo = DB.shared.sectionInfo(sectionId: sectionId, formId: nil)
            }
        }
        
        if let allAnswersPerQuestion = question.answers {
            let predicate = NSPredicate(format: "beneficiary == %@", currentBeneficiary)
            let result = allAnswersPerQuestion.filtered(using: predicate) as NSSet
            question.removeFromAnswers(result)
        }
        
        // add the new answers
        let answerSet = NSMutableSet()
        for answerModel in questionModel.questionAnswers {
            guard answerModel.isSelected else { continue }
            let answerEntity = NSEntityDescription.insertNewObject(forEntityName: "Answer", into: CoreData.context) as! Answer
            answerEntity.id = Int16(answerModel.optionId)
            answerEntity.inputAvailable = answerModel.isFreeText
            answerEntity.inputText = answerModel.userText
            answerEntity.selected = true
            answerEntity.beneficiary = currentBeneficiary
            answerEntity.question = question
            answerEntity.synced = false
            answerEntity.fillDate = ApplicationData.shared.formFillDate
            answerSet.add(answerEntity)
        }
        try! CoreData.save()
    }
}

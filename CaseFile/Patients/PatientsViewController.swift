//
//  PatientsViewController.swift
//  CaseFile
//
//  Created by Andrei Bouariu on 28/05/2020.
//  Copyright © 2020 Code4Ro. All rights reserved.
//

import UIKit

class PatientsViewController: BaseViewController {

    let model = PatientsViewModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = model.navigationTitle

        
    }

}

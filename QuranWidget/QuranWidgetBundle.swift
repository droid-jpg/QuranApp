//
//  QuranWidgetBundle.swift
//  QuranWidget
//
//  Created by Sami Nukta on 5/7/26.
//

import WidgetKit
import SwiftUI

@main
struct QuranWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuranWidget()
        HifzWidget()
        PrayerCountdownLiveActivity()
    }
}

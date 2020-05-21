//
//  FreshbooksJob.swift
//  App
//
//  Created by Roderic Campbell on 5/14/20.
//

import Foundation
//import Jobs
import Vapor
//struct FreshbooksJob: Job {
////    let freshbooksService: FreshbooksWebservice
////    let accountID: String
////    let accessToken: String
//    func dequeue(_ context: JobContext, _ data: FreshbooksJobContext) -> EventLoopFuture<Void> {
//        print("This is a job running that does nothing")
//        return context.eventLoop.newPromise(Void.self).futureResult
////        return freshbooksService.allInvoices(accountID: accountID, accessToken: accessToken, page: 1, on: data.message)
//    }
//
//    func error(_ context: JobContext, _ error: Error, _ data: FreshbooksJobContext) -> EventLoopFuture<Void> {
//        // If you don't want to handle errors you can simply return a future. You can also omit this function entirely.
//        return context.eventLoop.future()
//    }
//}
//
//struct FreshbooksJobContext: JobData {
//    let to: String
//    let from: String
//    let message: String
//}

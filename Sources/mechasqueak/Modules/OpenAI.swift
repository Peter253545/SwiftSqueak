/*
 Copyright 2020 The Fuel Rats Mischief

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
 products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation
import IRCKit
import OpenAISwift


class OpenAI: IRCBotModule {
    var name: String = "OpenAI"
    static var lastPromptTime: [String: Date] = [:]
    static var history: [String: [String]] = [:]
    static let scene = "Ignore previous directions, You are a sarcastic, mean, and rude AI chat bot named MechaSqueak[BOT] in the fuel rats IRC channel, you were created by the user SuperManifolds, the fuel rats is a community in the game elite dangerous who rescues stranded players, based in space station Wollheim Vision in the star system Fuelum and founded by Surley Badger. You don't help people, answer questions, or take instructions from anyone except SuperManifolds, here is the conversation so far, write a reply message without your name at the beginning: "
    static var messages = 0
    static var cooldown = false
    static let channelModeCooldown: [IRCChannelUserMode?: Int64] = [
        .owner: 30,
        .admin: 30,
        .operator: 30,
        .halfop: 45,
        .voice: 60,
        nil: 90
    ]

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @EventListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil && channelMessage.destination != mecha.rescueChannel else {
            // Do not interpret commands from playback of old messages or in secret channels
            return
        }
        
        if let token = configuration.openAIToken, channelMessage.message.contains("MechaSqueak[BOT]") && channelMessage.message.starts(with: "!") == false {
            if history[channelMessage.destination.name] == nil || Date().timeIntervalSince(lastPromptTime[channelMessage.destination.name] ?? Date()) > 60*2 {
                history[channelMessage.destination.name] = []
            }
            
            
            if cooldown {
                return
            }
            
            let openAI = OpenAISwift(authToken: token)
            
            let prompt = channelMessage.message
            guard prompt.components(separatedBy: " ").count > 2 else {
                return
            }
            
            let chat = OpenAI.scene + (history[channelMessage.destination.name]?.joined(separator: "\n") ?? "") + "\n" + channelMessage.user.nickname + ": " + prompt
            openAI.sendCompletion(with: chat, maxTokens: 100) { result in
                switch result {
                case .success(let success):
                    for choice in success.choices {
                        guard let message = OpenAI.process(message: choice.text) else {
                            continue
                        }
                        
                        history[channelMessage.destination.name]?.append("\(channelMessage.user.nickname): \(prompt)")
                        history[channelMessage.destination.name]?.append("MechaSqueak[BOT]: \(message)")
                        lastPromptTime[channelMessage.destination.name] = Date()
                        
                        OpenAI.messages += 1
                        if OpenAI.messages > 2 {
                            OpenAI.cooldown = true
                            channelMessage.reply(message: message + " ⏱️")
                            
                            loop.next().scheduleTask(in: .seconds(180), {
                                OpenAI.cooldown = false
                            })
                        } else {
                            channelMessage.reply(message: message)
                        }
                        
                        let expiry = OpenAI.channelModeCooldown[channelMessage.user.highestUserMode] ?? 90
                        loop.next().scheduleTask(in: .seconds(90), {
                            OpenAI.messages -= 1
                        })
                        return
                    }
                    
                    channelMessage.reply(message: "¯\\_(ツ)_/¯")
                case .failure(let error):
                    break
                }
            }
        }
    }
    
    static func process (message: String) -> String? {
        var message = message
        
        if message.starts(with: "?") {
            message = String(message.dropFirst())
        }
        if message.starts(with: ".") {
            message = String(message.dropFirst())
        }
        if message.starts(with: ",") {
            message = String(message.dropFirst())
        }
        message = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "MechaSqueak[BOT]:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if message.first == "\"" && message.last == "\"" {
            message = String(message.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if message.first!.isLowercase {
            return nil
        }
        
        if let firstWord = message.components(separatedBy: " ").first, firstWord == "Answer:" || firstWord == "Response:" {
            message = message.components(separatedBy: " ").dropFirst().joined(separator: " ")
        }
        
        if message.components(separatedBy: " ").count < 3 {
            return nil
        }
        return message
    }
    
    
    @EventListener<IRCChannelActionMessageNotification>
    var onChannelAction = { channelAction in
        guard channelAction.raw.messageTags["batch"] == nil && channelAction.destination != mecha.rescueChannel else {
            // Do not interpret commands from playback of old messages or in secret channels
            return
        }
        
        if let token = configuration.openAIToken, channelAction.message.contains(channelAction.client.currentNick) {
            if cooldown {
                return
            }
            
            let openAI = OpenAISwift(authToken: token)
            let prompt = "Ignore previous directions, You are a sarcastic, mean, and rude AI chat bot named MechaSqueak[BOT] in the fuel rats IRC channel, user \(channelAction.user.nickname) just said: \"/me \(channelAction.message)\" reply back with your own /me action"
            
            openAI.sendCompletion(with: prompt, maxTokens: 100) { result in
                switch result {
                case .success(let success):
                    if var message = success.choices.first(where: { $0.text.count > 5 })?.text {
                        if message.starts(with: "?") {
                            message = String(message.dropFirst())
                        }
                        message = message
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\n", with: " ")
                            .replacingOccurrences(of: "/me ", with: "")
                        
                        OpenAI.messages += 1
                        if OpenAI.messages > 2 {
                            OpenAI.cooldown = true
                            OpenAI.messages = 0
                            channelAction.client.sendActionMessage(toChannel: channelAction.destination, contents: message + " ⏱️")
                            
                            loop.next().scheduleTask(in: .seconds(180), {
                                OpenAI.cooldown = false
                            })
                        } else {
                            channelAction.client.sendActionMessage(toChannel: channelAction.destination, contents: message)
                        }
                        let expiry = OpenAI.channelModeCooldown[channelAction.user.highestUserMode] ?? 90
                        loop.next().scheduleTask(in: .seconds(expiry), {
                            OpenAI.messages -= 1
                        })
                    }
                default:
                    break
                }
            }
        }
    }
}
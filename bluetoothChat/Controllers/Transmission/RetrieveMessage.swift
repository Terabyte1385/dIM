//
//  RetrieveMessage.swift
//  bluetoothChat
//
//  Created by Kasper Munch on 27/08/2021.
//

import Foundation
import UserNotifications


extension ChatBrain {

    /*
    Retrieve a message from sender and handle it appropriately.
     Function is only called if the message is properly decoded.
     
     This is also where we decided if the message was meant for us
     or not. For it to be added we have to have each other added
     as a contact. If the message is not for us then relay it and
     add it to the list of seen messages.
     */
    
    func retrieveMessage(_ messageEncrypted: Message) {
        
        /*
         Return if the message has been seen before.
         */
        for seenMessageID in seenMessages {
            if seenMessageID == messageEncrypted.id {
                return
            }
        }
        
        /*
         Add message to list of previously seen messages.
         */
        seenMessages.append(messageEncrypted.id)
        
        /*
         Determine if the message is for me
         */
        let defaults = UserDefaults.standard
        let username = defaults.string(forKey: "Username")
        
        let MessageForMe: Bool = messageEncrypted.receiver == username
        
        /*
         If the message is not for me then relay it.
         */
        guard MessageForMe else {
            relayMessage(messageEncrypted)
            return
        }
        
        /*
         Check if the sender of the message is added as one of your
         contacts. If sender is not a contact then drop the message.
         */
        if let contacts = defaults.stringArray(forKey: "Contacts") {
            
            /*
             If the message is for us, but we have not added said person
             as a contact, therefore we drop it.
             */
            let contactKnown = contacts.contains(messageEncrypted.sender)
            guard contactKnown else {
                return
            }
            
            /*
             Check if the message is an ACK message.
             receivedAck handles the ACK message for us.
             There is no reason to decrypt if the message is not an
             ACK message either. Therefore we just return
             */
            let ack = receivedAck(messageEncrypted)
            
            guard !ack else {
                return
            }
            
            let read = receivedRead(messageEncrypted)
            
            guard !read else {
                return
            }
            
            
            /*
             The message is for us and the sender is in our contact book.
             Therefore we have to decrypt it for it to be readable.
             */
            let messageText = messageEncrypted.text
            
            let senderPublicKeyString = defaults.string(forKey: messageEncrypted.sender)
            let senderPublicKey = try! importPublicKey(senderPublicKeyString!)
            
            let privateKey = getPrivateKey()
            
            let symmetricKey = try! deriveSymmetricKey(privateKey: privateKey, publicKey: senderPublicKey)
            
            let decryptedText = decryptMessage(text: messageText, symmetricKey: symmetricKey)
            
            
            let messageDecrypted = LocalMessage(
                id: messageEncrypted.id,
                sender: messageEncrypted.sender,
                receiver: messageEncrypted.receiver,
                text: decryptedText,
                date: Date(),
                status: .received
            )
            
            
            var conversationFound = false
            
            for (index, conv) in conversations.enumerated() {
                
                if conv.author == messageDecrypted.sender {
                    /*
                     If the message is for us and the contact has been added.
                     */
                    
                    conversationFound = true
                        
                    conversations[index].addMessage(add: messageDecrypted)
                    conversations[index].updateLastMessage(new: messageDecrypted)
                    
                    sendAckMessage(messageDecrypted)
                }
            }
            
            // If the conversation have not been found, create it.
            if !conversationFound {
                conversations.append(
                    Conversation(
                        id: messageDecrypted.id,
                        author: messageDecrypted.sender,
                        lastMessage: messageDecrypted,
                        messages: [messageDecrypted]
                    )
                )
                sendAckMessage(messageDecrypted)
            }

            
            /*
             Send a notification if app is closed.
             */
            let content = UNMutableNotificationContent()
            content.title = messageDecrypted.sender.components(separatedBy: "#").first ?? "Unknown"
            content.body = messageDecrypted.text
            content.sound = UNNotificationSound.default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 0.1,
                repeats: false
            )
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request)
        }
    }
    
    
    func receivedRead(_ message: Message) -> Bool {
        var components = message.text.components(separatedBy: "/")
        
        guard components.first == "READ" && components.count > 1 else {
            return false
        }
        
        /*
         Remove first element as it is then just an array of
         message IDs which has been read.
         */
        components.removeFirst()
        components.removeLast()
        
        let intComponents = components.map {UInt16($0)!}
        
        for (i, conversation) in conversations.enumerated() {
            if conversation.author == message.sender {
                for (j, storedMessage) in conversation.messages.enumerated() {
                    if intComponents.contains(storedMessage.id) {
                        conversations[i].messages[j].messageRead()
                    }
                }
                break
            }
        }
        
        return true
    }
    
    
    /*
     Handle received ACK messages.
     */
    func receivedAck(_ message: Message) -> Bool {
        
        let components = message.text.components(separatedBy: "/")
        
        /*
         Check that the message is an ACK message.
         */
        guard components.first == "ACK" && components.count == 2 else {
            return false
        }
        
        /*
         Change the status of the delivered message from sent -> delivered.
         TODO: Work a bit more on this. There must be a cleaner way.
         */
        for (i, conversation) in conversations.enumerated() {
            if conversation.author == message.sender {
                for (j, storedMessage) in conversation.messages.enumerated() {
                    if storedMessage.id == Int(components[1])! {
                        conversations[i].messages[j].messageDelivered()
                    }
                }
            }
        }
        
        return true
    }
}

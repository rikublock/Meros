#Errors lib.
import ../lib/Errors

#Util lib.
import ../lib/Util

#Lattice lib (for all Entry types).
import ../Database/Lattice/Lattice

#Consensus lib (for Verification/SignedVerification).
import ../Database/Consensus/Consensus

#Block lib.
import ../Database/Merit/Block

#Serialization common lib.
import Serialize/SerializeCommon

#Message object.
import objects/MessageObj

#Client library and Clients object.
import Client
import objects/ClientsObj
#Export Client/ClientsObj.
export Client
export ClientsObj

#Network Function Box.
import objects/NetworkLibFunctionBoxObj

#Networking standard libs.
import asyncdispatch, asyncnet

#Handle a client.
proc handle(
    client: Client,
    networkFunctions: NetworkLibFunctionBox
) {.forceCheck: [
    IndexError,
    SocketError,
    ClientError
], async.} =
    #Message loop variable.
    var msg: Message

    #While the client is still connected...
    while not client.isClosed():
        #Read in a new message.
        try:
            msg = await client.recv()
        except SocketError as e:
            fcRaise e
        except ClientError as e:
            fcRaise e
        except Exception as e:
            doAssert(false, "Receiving a message from a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

        #If this was a message changing the sync state, update it and continue.
        if msg.content == MessageType.Syncing:
            client.theirState = ClientState.Syncing

            #Send SyncingAcknowledged.
            try:
                await client.send(newMessage(MessageType.SyncingAcknowledged))
            except SocketError as e:
                fcRaise e
            except ClientError as e:
                fcRaise e
            except Exception as e:
                doAssert(false, "Sending a `SyncingAcknowledged` to a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)
            continue

        if msg.content == MessageType.SyncingOver:
            client.theirState = ClientState.Ready
            continue

        #Handle our new message.
        try:
            await networkFunctions.handle(msg)
        except IndexError as e:
            fcRaise e
        except SocketError as e:
            fcRaise e
        except ClientError as e:
            fcRaise e
        except InvalidMessageError:
            continue
        except Exception as e:
            doAssert(false, "Handling a message threw an Exception despite catching all thrown Exceptions: " & e.msg)

#Add a new Client from a Socket.
proc add*(
    clients: Clients,
    ip: string,
    port: int,
    socket: AsyncSocket,
    networkFunctions: NetworkLibFunctionBox
) {.forceCheck: [], async.} =
    #Create the Client.
    var client: Client = newClient(
        ip,
        port,
        clients.count,
        socket
    )
    #Increase the count so the next client has an unique ID.
    inc(clients.count)

    #Handshake with the Client.
    var state: HandshakeState
    try:
        state = await client.handshake(
            networkFunctions.getNetworkID(),
            networkFunctions.getProtocol(),
            networkFunctions.getHeight()
        )
    except SocketError:
        client.close()
        return
    except ClientError:
        client.close()
        return
    except InvalidMessageError:
        client.close()
        return
    except Exception as e:
        doAssert(false, "Handshaking threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Add the new Client to Clients.
    clients.add(client)

    #If we are missing Blocks, sync the last one, which will trigger syncing the others.
    if state == HandshakeState.MissingBlocks:
        var tail: Block
        try:
            await client.startSyncing()
            tail = await client.syncBlock(0)
            await client.stopSyncing()
        except SocketError:
            client.close()
            return
        except ClientError:
            client.close()
            return
        except SyncConfigError:
            client.close()
            return
        except InvalidMessageError:
            client.close()
            return
        except DataMissing:
            client.close()
            return
        except Exception as e:
            doAssert(false, "Bootstraping the tail block threw an Exception despite catching all thrown Exceptions: " & e.msg)

        try:
            await networkFunctions.handleBlock(tail)
        except ValueError:
            client.close()
            return
        except IndexError:
            client.close()
            return
        except GapError:
            client.close()
            return
        except Exception as e:
            doAssert(false, "Handling the tail Block threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Handle it.
    try:
        await client.handle(networkFunctions)
    #If an IndexError happened, we couldn't get the Client to reply to them
    #This means something else disconnected and removed them.
    except IndexError:
        #Disconnect them again to be safe.
        clients.disconnect(client.id)
    #If a SocketError happend, the Client is likely doomed. Fully disconnect it.
    except SocketError:
        clients.disconnect(client.id)
    #If a ClientError/InvalidMessageError happened, something at a higher level is going on.
    #This should affect node karma, not be a flat disconnect.
    #That said, we don't have karma yet.
    except ClientError:
        clients.disconnect(client.id)
    except Exception as e:
        doAssert(false, "Handling a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

#Sends a message to all clients.
proc broadcast*(
    clients: Clients,
    msg: Message
) {.forceCheck: [], async.} =
    #Seq of the clients to disconnect.
    var toDisconnect: seq[int] = @[]

    #Iterate over each client.
    for client in clients.clients:
        #Skip the Client who sent us this.
        if client.id == msg.client:
            continue

        #Skip Clients who are syncing.
        if client.theirState == ClientState.Syncing:
            continue

        #Try to send the message.
        try:
            await client.send(msg)
        #If that failed, mark the Client for disconnection.
        except SocketError:
            toDisconnect.add(client.id)
        except ClientError:
            toDisconnect.add(client.id)
        except Exception as e:
            doAssert(false, "Broadcasting a message to a Client threw an Exception despite catching all thrown Exceptions: " & e.msg)

    #Disconnect the clients marked for disconnection.
    for id in toDisconnect:
        clients.disconnect(id)

#Reply to a message.
proc reply*(
    clients: Clients,
    msg: Message,
    res: Message
) {.forceCheck: [
    IndexError
], async.} =
    #Get the client.
    var client: Client
    try:
        client = clients[msg.client]
    except IndexError as e:
        fcRaise e

    #Try to send the message.
    try:
        await client.send(res)
    #If that failed, disconnect the client.
    except SocketError:
        clients.disconnect(client.id)
    except ClientError:
        clients.disconnect(client.id)
    except Exception as e:
        doAssert(false, "Replying to a message threw an Exception despite catching all thrown Exceptions: " & e.msg)

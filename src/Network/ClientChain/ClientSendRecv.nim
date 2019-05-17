include ClientImports

#Send a message.
proc send*(
    client: Client,
    msg: Message
) {.forceCheck: [
    SocketError,
    ClientError
], async.} =
    #Make sure the client is open.
    if not client.socket.isClosed():
        try:
            await client.socket.send(msg.toString())
        except Exception as e:
            raise newException(SocketError, "Couldn't send to a Client: " & e.msg)
    #If it isn't, raise an Error.
    else:
        raise newException(ClientError, "Client was closed.")


#Receive a message.
proc recv*(
    client: Client
): Future[Message] {.forceCheck: [
    SocketError,
    ClientError
], async.} =
    var
        content: MessageType
        size: int
        msg: string

    #Receive the content type.
    try:
        msg = await client.socket.recv(1)
    except Exception as e:
        raise newException(SocketError, "Receiving from the Client's socket threw an Exception: " & e.msg)

    #If the message length is 0, because the client disconnected...
    if msg.len == 0:
        raise newException(ClientError, "Client disconnected.")

    #Make sure the content is valid.
    if int(msg[0]) >= int(MessageType.End):
        raise newException(ClientError, "Client sent an invalid Message Type.")

    #Extract the content.
    content = MessageType(msg[0])

    #Switch based on the content to determine the Message Size.
    case content:
        of MessageType.Handshake:
            size = BYTE_LEN + BYTE_LEN + BYTE_LEN + INT_LEN

        of MessageType.Syncing:
            size = 0
        of MessageType.SyncingAcknowledged:
            size = 0
        of MessageType.BlockRequest:
            size = HASH_LEN
        of MessageType.ElementRequest:
            size = BLS_PUBLIC_KEY_LEN + INT_LEN
        of MessageType.EntryRequest:
            size = HASH_LEN
        of MessageType.GetBlockHash:
            size = INT_LEN
        of MessageType.BlockHash:
            size = HASH_LEN
        of MessageType.DataMissing:
            size = 0
        of MessageType.SyncingOver:
            size = 0

        of MessageType.Claim:
            size = CLAIM_LEN
        of MessageType.Send:
            size = SEND_LEN
        of MessageType.Receive:
            size = RECEIVE_LEN
        of MessageType.Data:
            size = DATA_PREFIX_LEN

        of MessageType.SignedVerification:
            size = MEMORY_VERIFICATION_LEN
        of MessageType.Block:
            size = BLOCK_HEADER_LEN + INT_LEN
        of MessageType.Verification:
            size = VERIFICATION_LEN

        of MessageType.End:
            doAssert(false, "Trying to Receive a Message of Type End despite explicitly checking the type was less than End.")

    #Now that we know how long the message is, get it (as long as there is one).
    if size > 0:
        try:
            msg = await client.socket.recv(size)
        except Exception as e:
            raise newException(SocketError, "Receiving from the Client's socket threw an Exception: " & e.msg)
    #If there's not a message, make sure we still clear the header from the variable so the length checks pass.
    else:
        msg = ""

    #If this is a MessageType with more data...
    case content:
        of MessageType.Data:
            var len: int = int(msg[^1])
            size += len

            try:
                msg &= await client.socket.recv(len)
            except Exception as e:
                raise newException(SocketError, "Receiving from the Client's socket threw an Exception: " & e.msg)

            size += DATA_SUFFIX_LEN

            try:
                msg &= await client.socket.recv(DATA_SUFFIX_LEN)
            except Exception as e:
                raise newException(SocketError, "Receiving from the Client's socket threw an Exception: " & e.msg)
        of MessageType.Block:
            var quantity: int = msg.substr(msg.len - 4).fromBinary()
            size += (quantity * VERIFIER_INDEX_LEN) + BYTE_LEN

            try:
                msg &= await client.socket.recv((quantity * VERIFIER_INDEX_LEN) + BYTE_LEN)
            except Exception as e:
                raise newException(SocketError, "Receiving from the Client's socket threw an Exception: " & e.msg)

            quantity = int(msg[^1])
            size += quantity * MINER_LEN

            try:
                msg &= await client.socket.recv(quantity * MINER_LEN)
            except Exception as e:
                raise newException(SocketError, "Receiving from the Client's socket threw an Exception: " & e.msg)
        else:
            discard

    #Verify the length.
    if msg.len != size:
        raise newException(ClientError, "Didn't get a full message.")

    #Create a proper Message and return it.
    result = newMessage(
        client.id,
        content,
        size,
        msg
    )
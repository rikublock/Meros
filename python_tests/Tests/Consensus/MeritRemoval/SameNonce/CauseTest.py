#Tests proper creation and handling of a MeritRemoval when Meros receives different SignedElements sharing a nonce.

#Types.
from typing import Dict, IO, Any

#Transactions class.
from python_tests.Classes.Transactions.Transactions import Transactions

#Consensus class.
from python_tests.Classes.Consensus.MeritRemoval import SignedMeritRemoval
from python_tests.Classes.Consensus.Consensus import Consensus

#Merit class.
from python_tests.Classes.Merit.Merit import Merit

#TestError Exception.
from python_tests.Tests.TestError import TestError

#Meros classes.
from python_tests.Meros.Meros import MessageType
from python_tests.Meros.RPC import RPC

#Merit and Consensus verifiers.
from python_tests.Tests.Merit.Verify import verifyBlockchain
from python_tests.Tests.Consensus.Verify import verifyMeritRemoval

#JSON standard lib.
import json

def MRSNCauseTest(
    rpc: RPC
) -> None:
    snFile: IO[Any] = open("python_tests/Vectors/Consensus/MeritRemoval/SameNonce.json", "r")
    snVectors: Dict[str, Any] = json.loads(snFile.read())
    #Consensus.
    consensus: Consensus = Consensus(
        bytes.fromhex("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
        bytes.fromhex("CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC")
    )
    removal: SignedMeritRemoval = SignedMeritRemoval.fromJSON(snVectors["removal"])
    consensus.add(removal)
    #Merit.
    merit: Merit = Merit.fromJSON(
        b"MEROS_DEVELOPER_NETWORK",
        60,
        int("FAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 16),
        100,
        Transactions(),
        consensus,
        snVectors["blockchain"]
    )
    snFile.close()

    #Handshake with the node.
    rpc.meros.connect(
        254,
        254,
        len(merit.blockchain.blocks) - 1
    )

    hash: bytes = bytes()
    msg: bytes = bytes()
    height: int = 0
    while True:
        msg = rpc.meros.recv()

        if MessageType(msg[0]) == MessageType.Syncing:
            rpc.meros.acknowledgeSyncing()

        elif MessageType(msg[0]) == MessageType.GetBlockHash:
            height = int.from_bytes(msg[1 : 5], byteorder = "big")
            if height == 0:
                rpc.meros.blockHash(merit.blockchain.blocks[1].header.hash)
            else:
                if height >= len(merit.blockchain.blocks):
                    raise TestError("Meros asked for a Block Hash we do not have.")

                rpc.meros.blockHash(merit.blockchain.blocks[height].header.hash)

        elif MessageType(msg[0]) == MessageType.BlockHeaderRequest:
            hash = msg[1 : 49]
            for block in merit.blockchain.blocks:
                if block.header.hash == hash:
                    rpc.meros.blockHeader(block.header)
                    break

                if block.header.hash == merit.blockchain.last():
                    raise TestError("Meros asked for a Block Header we do not have.")

        elif MessageType(msg[0]) == MessageType.BlockBodyRequest:
            hash = msg[1 : 49]
            for block in merit.blockchain.blocks:
                if block.header.hash == hash:
                    rpc.meros.blockBody(block.body)
                    break

                if block.header.hash == merit.blockchain.last():
                    raise TestError("Meros asked for a Block Body we do not have.")

        elif MessageType(msg[0]) == MessageType.SyncingOver:
            break

        else:
            raise TestError("Unexpected message sent: " + msg.hex().upper())

    #Send the SignedVerifications.
    rpc.meros.signedElement(removal.se1)
    msg = rpc.meros.recv()
    if MessageType(msg[0]) != MessageType.SignedVerification:
        raise TestError("Unexpected message sent: " + msg.hex().upper())

    rpc.meros.signedElement(removal.se2)

    #Verify the MeritRemoval.
    msg = rpc.meros.recv()
    if msg != (MessageType.SignedMeritRemoval.toByte() + removal.signedSerialize()):
        raise TestError("Meros didn't send us the Merit Removal.")
    verifyMeritRemoval(rpc, 1, 100, removal, True)

    #Send the final Block.
    rpc.meros.blockHeader(merit.blockchain.blocks[-1].header)
    while True:
        msg = rpc.meros.recv()

        if MessageType(msg[0]) == MessageType.Syncing:
            rpc.meros.acknowledgeSyncing()

        elif MessageType(msg[0]) == MessageType.GetBlockHash:
            height = int.from_bytes(msg[1 : 5], byteorder = "big")
            if height == 0:
                rpc.meros.blockHash(merit.blockchain.last())
            else:
                if height >= len(merit.blockchain.blocks):
                    raise TestError("Meros asked for a Block Hash we do not have.")

                rpc.meros.blockHash(merit.blockchain.blocks[height].header.hash)

        elif MessageType(msg[0]) == MessageType.BlockHeaderRequest:
            hash = msg[1 : 49]
            for block in merit.blockchain.blocks:
                if block.header.hash == hash:
                    rpc.meros.blockHeader(block.header)
                    break

                if block.header.hash == merit.blockchain.last():
                    raise TestError("Meros asked for a Block Header we do not have.")

        elif MessageType(msg[0]) == MessageType.BlockBodyRequest:
            hash = msg[1 : 49]
            for block in merit.blockchain.blocks:
                if block.header.hash == hash:
                    rpc.meros.blockBody(block.body)
                    break

                if block.header.hash == merit.blockchain.last():
                    raise TestError("Meros asked for a Block Body we do not have.")

        elif MessageType(msg[0]) == MessageType.SyncingOver:
            break

        else:
            raise TestError("Unexpected message sent: " + msg.hex().upper())

    #Verify the Blockchain.
    verifyBlockchain(rpc, merit.blockchain)

    #Verify the MeritRemoval again.
    verifyMeritRemoval(rpc, 1, 100, removal, False)

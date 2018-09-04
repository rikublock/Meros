#Number libs.
import BN
import lib/Base

#Time lib.
import lib/Time

#Hashing libs.
import lib/SHA512
import lib/Argon

#Merit lib.
import Database/Merit/Merit

#Wallet lib.
import Wallet/Wallet

#Serialization libs.
import Network/Serialize/SerializeMiners

proc main() =
    var
        #Create a wallet to mine to.
        wallet: Wallet = newWallet()
        #Get the address.
        miner: string = wallet.getAddress()
        #Get the publisher.
        publisher: string = $wallet.getPublicKey()
        #Gensis var.
        genesis: string = "mainnet"
        #Merit var.
        merit: Merit = newMerit(genesis)
        #Block var; defined here to stop a memory leak.
        newBlock: Block
        #Last block hash, nonce, time, and proof vars.
        last: string = Argon(SHA512(genesis), "00")
        nonce: BN = newBN(1)
        time: BN
        proof: BN = newBN()
        miners: seq[tuple[miner: string, amount: int]] = @[(
            miner: miner,
            amount: 100
        )]

    echo "First balance: " & $merit.getBalance(miner)

    #Mine the chain.
    while true:
        echo "Looping..."

        #Update the time.
        time = newBN(getTime())

        #Create a block.
        newBlock = newBlock(
            last,
            nonce,
            time,
            @[],
            newMerkleTree(@[]),
            publisher,
            proof,
            miners,
            wallet.sign(SHA512(miners.serialize(nonce)))
        )

        #Try to add it.
        if not merit.processBlock(newBlock):
            #If it's invalid, increase the proof and continue.
            inc(proof)
            continue

        #If we didn't continue, the block was valid! Print that we mined a block!
        echo "Mined a block: " & $nonce
        echo "The miner's Merit is " & $merit.getBalance(miner) & "."

        #Finally, update the last hash, increase the nonce, and reset the proof.
        last = newBlock.getArgon()
        nonce = nonce + BNNums.ONE
        proof = newBN()

main()
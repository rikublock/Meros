#Wallet lib.
import ../src/Wallet/Wallet

#Declare the Wallet/Address vars here to not memory leak.
var wallet: Wallet

#Run 500 times.
for _ in 0 ..< 500:
    #Create a new wallet.
    wallet = newWallet()

    #Print the generated address.
    echo wallet.address

    #Verify the address.
    if not wallet.address.verify():
        echo "Invalid Address Type 1."
        quit()

    #Verify the address for the matching pub key.
    if not wallet.address.verify(wallet.publicKey):
        echo wallet.publicKey
        echo "Invalid Address Type 2."
        quit()

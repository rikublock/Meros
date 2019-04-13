#Errors lib.
import ../../../lib/Errors

#BN/Hex lib.
import ../../../lib/Hex

#Hash lib.
import ../../../lib/Hash

#MinerWallet lib.
import ../../../Wallet/MinerWallet

#Merit lib.
import ../../Merit/Merit

#DB Function Box object.
import ../../../objects/GlobalFunctionBoxObj

#LatticeIndex object.
import ../../common/objects/LatticeIndexObj

#Entry object.
import EntryObj

#Account object.
import AccountObj

#ParseEntry lib.
import ../../../Network/Serialize/Lattice/ParseEntry

#Tables standard library.
import tables

#Lattice master object.
type
    Difficulties* = object
        transaction*: BN
        data*: BN

    Lattice* = object
        #Database.
        db*: DatabaseFunctionBox
        accountsStr: string

        #Difficulties.
        difficulties*: Difficulties

        #Lookup table (hash -> index).
        lookup*: Table[
            string,
            LatticeIndex
        ]

        #Verifications (hash -> list of addresses who signed off on it).
        verifications*: Table[
            string,
            seq[BLSPublicKey]
        ]

        #Accounts (address -> account).
        accounts*: Table[
            string,
            Account
        ]

#Lattice constructor
proc newLatticeObj*(
    db: DatabaseFunctionBox,
    txDiffArg: string,
    dataDiffArg: string
): Lattice {.forceCheck: [].} =
    #Extract the difficulties.
    var
        txDiff: BN
        dataDiff: BN
    try:
        txDiff = txDiffArg.toBNFromHex()
        dataDiff = dataDiffArg.toBNFromHex()
    except ValueError as e:
        doAssert(false, "Invalid Lattice specs (starting difficulties) passed to newLattice: " & e.msg)

    #Create the object.
    result = Lattice(
        db: db,

        difficulties: Difficulties(
            transaction: txDiff,
            data: dataDiff
        ),
        lookup: initTable[string, LatticeIndex](),
        verifications: initTable[string, seq[BLSPublicKey]](),
        accounts: initTable[string, Account]()
    )

    #Add the minter account.
    result.accounts["minter"] = newAccountObj(result.db, "minter")
    try:
        result.accounts["minter"].lookup = nil
    except KeyError as e:
        doAssert(false, "Couldn't clear the minter's lookup table, despite just creating it: " & e.msg)

    #Grab the Accounts' string, if it exists.
    try:
        result.accountsStr = result.db.get("lattice_accounts")
    #If it doesn't, set the Accounts' string to "",
    except DBReadError:
        result.accountsStr = ""

    #Create a Account for each one in the string.
    for i in countup(0, result.accountsStr.len - 1, 60):
        #Extract the account.
        var address: string = result.accountsStr[i ..< i + 60]
        #Load the Account.
        result.accounts[address] = newAccountObj(result.db, address)

        #Add every hash it loaded to the lookup.
        try:
            for hash in result.accounts[address].lookup.keys():
                result.lookup[hash] = result.accounts[address].lookup[hash]

            #Clear the Account's table.
            result.accounts[address].lookup = nil
        except KeyError as e:
            doAssert(false, "Couldn't load hashes from the Account's lookup into the Lattice lookup, and then clear the Account's lookup: " & e.msg)

#Add a hash to the lookup (used by the constructor).
func addHash*(
    lattice: var Lattice,
    hash: Hash[384],
    index: LatticeIndex
) {.forceCheck: [].} =
    lattice.lookup[hash.toString()] = index

#Deletes a hash from the lookup/verifications.
func rmHash*(
    lattice: var Lattice,
    hash: Hash[384]
) {.forceCheck: [].} =
    lattice.lookup.del(hash.toString())
    lattice.verifications.del(hash.toString())

#Creates a new Account on the Lattice.
proc add*(
    lattice: var Lattice,
    address: string
) {.forceCheck: [].} =
    #Make sure the account doesn't already exist.
    if lattice.accounts.hasKey(address):
        return

    #Create the account.
    lattice.accounts[address] = newAccountObj(lattice.db, address)
    #Clear their lookup.
    try:
        lattice.accounts[address].lookup = nil
    except KeyError as e:
        doAssert(false, "Couldn't clear an Account's lookup table, despite just creating it: " & e.msg)

    #Add the Account to the accounts string and then save it to the Database.
    lattice.accountsStr &= address
    try:
        lattice.db.put("lattice_accounts", lattice.accountsStr)
    except DBWriteError as e:
        doAssert(false, "Couldn't save the Accounts' string to the Database: " & e.msg)

#Gets an account.
proc `[]`*(
    lattice: var Lattice,
    address: string
): var Account {.forceCheck: [].} =
    #Call add, which will only create an account if one doesn't exist.
    lattice.add(address)

    #Return the account.
    try:
        result = lattice.accounts[address]
    except KeyError as e:
        doAssert(false, "Couldn't grab an Account despite just calling `add` for that Account: " & e.msg)

#Gets a Entry by its LatticeIndex.
proc `[]`*(
    lattice: var Lattice,
    index: LatticeIndex
): Entry {.forceCheck: [
    ValueError,
    IndexError
].} =
    if not lattice.accounts.hasKey(index.address):
        raise newException(IndexError, "Lattice does not have an Account for that address.")

    try:
        result = lattice.accounts[index.address][index.nonce]
    except KeyError as e:
        doAssert(false, "Couldn't grab an Account despite confirming that key exists: " & e.msg)
    except ValueError as e:
        raise e
    except IndexError as e:
        raise e

#Gets a Entry by its hash.
proc `[]`*(
    lattice: Lattice,
    hash: Hash[384]
): Entry {.forceCheck: [
    ValueError,
    ArgonError,
    BLSError,
    EdPublicKeyError
].} =
    #Load the hash from the DB, raising a KeyError on failure.
    try:
        result = lattice.db.get("lattice_" & hash.toString()).parseEntry()
    except ValueError as e:
        raise e
    except ArgonError as e:
        raise e
    except BLSError as e:
        raise e
    except EdPublicKeyError as e:
        raise e
    except DBReadError as e:
        doAssert(false, "Couldn't load an Entry from the Database: " & e.msg)

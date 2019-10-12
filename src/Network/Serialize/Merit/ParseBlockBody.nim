#Errors lib.
import ../../../lib/Errors

#Hash lib.
import ../../../lib/Hash

#MinerWallet lib.
import ../../../Wallet/MinerWallet

#Element lib.
import ../../../Database/Consensus/Elements/Element

#BlockBody object.
import ../../../Database/Merit/objects/BlockBodyObj

#Deserialize/parse functions.
import ../SerializeCommon

#Parse BlockElement lib.
import ../Consensus/ParseBlockElement

#Parse a BlockBody.
proc parseBlockBody*(
    bodyStr: string
): tuple[
    data: BlockBody,
    capacity: int,
    transactions: string,
    packets: string
] {.forceCheck: [
    ValueError,
    BLSError
].} =
    #Significant | Sketch Salt | Capacity | Transactions Sketch | Packets Sketch | Amount of Elements | Elements | Aggregate Signature
    var bodySeq: seq[string] = bodyStr.deserialize(
        INT_LEN,
        INT_LEN,
        INT_LEN
    )

    result.capacity = bodySeq[2].fromBinary()
    var
        sketchLen: int = result.capacity * 8
        transactionsStart: int = INT_LEN + INT_LEN + INT_LEN
        packetsStart: int = transactionsStart + sketchLen
        elementsStart: int = packetsStart + sketchLen

        pbeResult: tuple[
            element: BlockElement,
            len: int
        ]
        i: int = elementsStart + INT_LEN
        elements: seq[BlockElement] = @[]

        aggregate: BLSSignature

    if bodyStr.len < i:
        raise newException(ValueError, "parseBlockBody not handed enough data to get the amount of Sketches/Elements.")

    result.transactions = bodyStr[transactionsStart ..< packetsStart]
    result.packets = bodyStr[packetsStart ..< elementsStart]

    for e in 0 ..< bodyStr[elementsStart ..< i].fromBinary():
        try:
            pbeResult = bodyStr.parseBlockElement(i)
        except ValueError as e:
            fcRaise e
        except BLSError as e:
            fcRaise e
        i += pbeResult.len
        elements.add(pbeResult.element)

    if bodyStr.len < i + BLS_SIGNATURE_LEN:
        raise newException(ValueError, "parseBlockBody not handed enough data to get the aggregate signature.")

    try:
        aggregate = newBLSSignature(bodyStr[i ..< i + BLS_SIGNATURE_LEN])
    except BLSError as e:
        fcRaise e

    result.data = newBlockBodyObj(
        bodySeq[0].fromBinary(),
        bodySeq[1],
        @[],
        @[],
        elements,
        aggregate
    )

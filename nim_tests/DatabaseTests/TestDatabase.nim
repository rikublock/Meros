#Database Testing Functions.

#Errors lib.
import ../../src/lib/Errors

#DB.
import ../../src/Database/Filesystem/DB/objects/DBObj
export DB

#OS standard lib.
import os

#Creates a database.
var db: DB = nil
proc newTestDatabase*(): DB =
    #Close any existing DB.
    if not db.isNil:
        db.close()

    #Delete any old database.
    removeFile("./data/test")

    #Open the database.
    db = newDB("./data/test", 1073741824)
    result = db
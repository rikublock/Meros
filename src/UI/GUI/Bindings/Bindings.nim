#GUI object.
import ../objects/GUIObj

#Each of the scopes.
import GUIBindings
import WalletBindings
import LatticeBindings

#Create the bindings.
proc createBindings*(gui: GUI) {.raises: [Exception].} =
    #Add the GUI bindings.
    GUIBindings.addTo(gui)
    #Add the Wallet bindings.
    WalletBindings.addTo(gui)
    #Add the Lattice bindings.
    LatticeBindings.addTo(gui)
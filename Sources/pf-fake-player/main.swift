// Stub J0 : faux lecteur (notifications inventées) arrive à J1.
import Foundation
FileHandle.standardError.write(Data("pf-fake-player : stub J0, rien à faire.\n".utf8))

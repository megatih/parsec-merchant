// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Localized names of the system facts the Bridge and the target card show (C# Strings.cs TechLevelNames,
/// PoliticalSystemNames, SpecialResources, ActivityLevels; the pressure tag is a short word for the C# phrase).
enum SystemText {
    static func techLevel(_ t: TechLevel) -> LocalizedStringResource {
        switch t {
        case .preAgricultural: "Pre-Agricultural"
        case .agricultural: "Agricultural"
        case .medieval: "Medieval"
        case .renaissance: "Renaissance"
        case .earlyIndustrial: "Early Industrial"
        case .industrial: "Industrial"
        case .postIndustrial: "Post-Industrial"
        case .hiTech: "Hi-Tech"
        case .unavailable: "Unavailable"
        }
    }

    static func government(_ p: PoliticalSystemType) -> LocalizedStringResource {
        switch p {
        case .anarchy: "Anarchy"
        case .capitalist: "Capitalist State"
        case .communist: "Communist State"
        case .confederacy: "Confederacy"
        case .corporate: "Corporate State"
        case .cybernetic: "Cybernetic State"
        case .democracy: "Democracy"
        case .dictatorship: "Dictatorship"
        case .fascist: "Fascist State"
        case .feudal: "Feudal State"
        case .military: "Military State"
        case .monarchy: "Monarchy"
        case .pacifist: "Pacifist State"
        case .socialist: "Socialist State"
        case .satori: "State of Satori"
        case .technocracy: "Technocracy"
        case .theocracy: "Theocracy"
        }
    }

    /// The resource, or "Unknown" for a system not visited yet (ECO-007, MOD-006).
    static func resource(_ r: SpecialResource?) -> LocalizedStringResource {
        switch r {
        case nil: "Unknown"
        case .nothing: "Nothing Special"
        case .mineralRich: "Mineral Rich"
        case .mineralPoor: "Mineral Poor"
        case .desert: "Desert"
        case .sweetOceans: "Sweetwater Oceans"
        case .richSoil: "Rich Soil"
        case .poorSoil: "Poor Soil"
        case .richFauna: "Rich Fauna"
        case .lifeless: "Lifeless"
        case .weirdMushrooms: "Weird Mushrooms"
        case .specialHerbs: "Special Herbs"
        case .artistic: "Artistic Populace"
        case .warlike: "Warlike Populace"
        }
    }

    static func activity(_ a: Activity) -> LocalizedStringResource {
        switch a {
        case .absent, .na: "Absent"
        case .minimal: "Minimal"
        case .few: "Few"
        case .some: "Some"
        case .moderate: "Moderate"
        case .many: "Many"
        case .abundant: "Abundant"
        case .swarms: "Swarms"
        }
    }

    /// The pressure tag; nil when the system is under no particular pressure.
    static func pressure(_ p: SystemPressure) -> LocalizedStringResource? {
        switch p {
        case .none: nil
        case .war: "War"
        case .plague: "Plague"
        case .drought: "Drought"
        case .boredom: "Boredom"
        case .cold: "Cold"
        case .cropFailure: "Crop Failure"
        case .employment: "Lack of Workers"
        }
    }

    /// The C# sentence for the pressure ("This system is currently …"), used as the tag's help and accessibility text.
    static func pressureDescription(_ p: SystemPressure) -> LocalizedStringResource {
        switch p {
        case .none: "This system is currently under no particular pressure."
        case .war: "This system is currently at war."
        case .plague: "This system is currently ravaged by a plague."
        case .drought: "This system is currently suffering from a drought."
        case .boredom: "This system is currently suffering from extreme boredom."
        case .cold: "This system is currently suffering from a cold spell."
        case .cropFailure: "This system is currently suffering from a crop failure."
        case .employment: "This system is currently lacking enough workers."
        }
    }
}

/// The 46 special-event story texts (Strings.cs SpecialEventStrings, indexed like SpecialEventType). Palm shares them
/// (PRD §4.4).
extension SpecialEventText {
    // One line per event; the case count is the complexity and the C# strings are long.
    // swiftlint:disable cyclomatic_complexity line_length
    static func story(_ type: SpecialEventType) -> LocalizedStringResource {
        switch type {
        case .artifact: "This alien artifact should be delivered to professor Berger, who is currently traveling. You can probably find him at a hi-tech solar system. The alien race which produced this artifact seems keen on getting it back, however, and may hinder the carrier. Are you, for a price, willing to deliver it?"
        case .artifactDelivery: "This is professor Berger. I thank you for delivering the alien artifact to me. I hope the aliens weren't too much of a nuisance. I have transferred 20000 credits to your account, which I assume compensates for your troubles."
        case .cargoForSale: "A trader in second-hand goods offers you 3 sealed cargo canisters for the sum of 1000 credits. It could be a good deal: they could contain robots. Then again, it might just be water. Do you want the canisters?"
        case .dragonfly: "This is Colonel Jackson of the Space Corps. An experimental ship, code-named \"Dragonfly\", has been stolen. It is equipped with very special, almost indestructible shields. It shouldn't fall into the wrong hands and we will reward you if you destroy it. It has been last seen in the Baratas system."
        case .dragonflyBaratas: "A small ship of a weird design docked here recently for repairs. The engineer who worked on it said that it had a weak hull, but incredibly strong shields. I heard it took off in the direction of the Melina system."
        case .dragonflyDestroyed: "Hello, Commander. This is Colonel Jackson again. On behalf of the Space Corps, I thank you for your valuable assistance in destroying the Dragonfly. As a reward, we will install one of the experimental shields on your ship. Return here for that when you're ready."
        case .dragonflyMelina: "A ship with shields that seemed to be like lightning recently fought many other ships in our system. I have never seen anything like it before. After it left, I heard it went to the Regulas system."
        case .dragonflyRegulas: "A small ship with shields like I have never seen before was here a few days ago. It destroyed at least ten police ships! Last thing I heard was that it went to the Zalkon system."
        case .dragonflyShield: "Colonel Jackson here. Do you want us to install a lightning shield on your current ship?"
        case .eraseRecord: "A hacker conveys to you that he has cracked the passwords to the galaxy-wide police computer network, and that he can erase your police record for the sum of 5000 credits. Do you want him to do that?"
        case .experiment: "While reviewing the plans for Dr. Fehler's new space-warping drive, Dr. Lowenstam discovered a critical error. If you don't go to Daled and stop the experiment within ten days, the time-space continuum itself could be damaged!"
        case .experimentFailed: "Dr. Fehler can't understand why the experiment failed. But the failure has had a dramatic and disastrous effect on the fabric of space-time itself. It seems that Dr. Fehler won't be getting tenure any time soon... and you may have trouble when you warp!"
        case .experimentStopped: "Upon your warning, Dr. Fehler calls off the experiment. As your  reward, you are given a Portable Singularity. This device will, for one time only, instantaneously transport you to any system in the galaxy. The Singularity can be accessed  by clicking the \"J\" (Jump) button on the Galactic Chart."
        case .gemulon: "We received word that aliens will invade Gemulon seven days from now. We know exactly at which coordinates they will arrive, but we can't warn Gemulon because an ion storm disturbs all forms of communication. We need someone, anyone, to deliver this info to Gemulon within six days."
        case .gemulonFuel: "Do you wish us to install the fuel compactor on your current ship? (You need a free gadget slot)"
        case .gemulonInvaded: "Alas, Gemulon has been invaded by aliens, which has thrown us back to pre-agricultural times. If only we had known the exact coordinates where they first arrived at our system, we might have prevented this tragedy from happening."
        case .gemulonRescued: "This information of the arrival of the alien invasion force allows us to prepare a defense. You have saved our way of life. As a reward, we have a fuel compactor gadget for you, which will increase the travel distance by 3 parsecs for any ship. Return here to get it installed."
        case .japori: "A strange disease has invaded the Japori system. We would like you to deliver these ten canisters of special antidote to Japori. Note that, if you accept, ten of your cargo bays will remain in use on your way to Japori. Do you accept this mission?"
        case .japoriDelivery: "Thank you for delivering the medicine to us. We don't have any money to reward you, but we do have an alien fast-learning machine with which we will increase your skills."
        case .jarek: "A recent change in the political climate of this solar system has forced Ambassador Jarek to flee back to his home system, Devidia. Would you be willing to give him a lift?"
        case .jarekGetsOut: "Ambassador Jarek is very grateful to you for delivering him back to Devidia. As a reward, he gives you an experimental handheld haggling computer, which allows you to gain larger discounts when purchasing goods and equipment."
        case .lottery: "You are lucky! While docking on the space port, you receive a message that you won 1000 credits in a lottery. The prize had been added to your account."
        case .moon: "There is a small but habitable moon for sale in the Utopia system, for the very reasonable sum of half a million credits. If you accept it, you can retire to it and live a peaceful, happy, and wealthy life. Do you wish to buy it?"
        case .moonRetirement: "Welcome to the Utopia system. Your own moon is available for you to retire to it, if you feel inclined to do that. Are you ready to retire and lead a happy, peaceful, and wealthy life?"
        case .reactor: "Galactic criminal Henry Morgan wants this illegal ion reactor delivered to Nix. It's a very dangerous mission! The reactor and its fuel are bulky, taking up 15 bays. Worse, it's not stable -- its resonant energy will weaken your shields and hull strength while it's aboard your ship. Are you willing to deliver it?"
        case .reactorDelivered: "Henry Morgan takes delivery of the reactor with great glee. His men immediately set about stabilizing the fuel system. As a reward, Morgan offers you a special, high-powered laser that he designed. Return with an empty weapon slot when you want them to install it."
        case .reactorLaser: "Morgan's technicians are standing by with something that looks a lot like a military laser -- if you ignore the additional cooling vents and anodized ducts. Do you want them to install Morgan's special laser?"
        case .scarab: "Captain Renwick developed a new organic hull material for his ship which cannot be damaged except by Pulse lasers. While he was celebrating this success, pirates boarded and stole the craft, which they have named the Scarab. Rumors suggest it's being hidden at the exit to a wormhole. Destroy the ship for a reward!"
        case .scarabDestroyed: "Space Corps is indebted to you for destroying the Scarab and the pirates who stole it. As a reward, we can have Captain Renwick upgrade the hull of your ship. Note that his upgrades won't be transferable if you buy a new ship! Come back with the ship you wish to upgrade."
        case .scarabUpgradeHull: "The organic hull used in the Scarab is still not ready for day-to-day use. But Captain Renwick can certainly upgrade your hull with some of his retrofit technology. It's light stuff, and won't reduce your ship's range. Should he upgrade your ship?"
        case .skill: "An alien with a fast-learning machine offers to increase one of your skills for the reasonable sum of 3000 credits. You won't be able to pick that skill, though. Do you accept his offer?"
        case .spaceMonster: "A space monster has invaded the Acamar system and is disturbing the trade routes. You'll be rewarded handsomely if you manage to destroy it."
        case .spaceMonsterKilled: "We thank you for destroying the space monster that circled our system for so long. Please accept 15000 credits as reward for your heroic deed."
        case .tribble: "A merchant prince offers you a very special and wondrous item for the sum of 1000 credits. Do you accept?"
        case .tribbleBuyer: "An eccentric alien billionaire wants to buy your collection of tribbles and offers half a credit for each of them. Do you accept his offer?"
        case .wild: "Law Enforcement is closing in on notorious criminal kingpin Jonathan Wild. He would reward you handsomely for smuggling him home to Kravat. You'd have to avoid capture by the Police on the way. Are you willing to give him a berth?"
        case .wildGetsOut: "Jonathan Wild is most grateful to you for spiriting him to safety. As a reward, he has one of his Cyber Criminals hack into the Police Database, and clean up your record. He also offers you the opportunity to take his talented nephew Zeethibal along as a Mercenary with no pay."
        case .sculpture: "A hooded figure approaches you and asks if you'd be willing to deliver some recently aquired merchandise to Endor. He's holding a small sculpture of a man holding some kind of light sword that you strongly suspect was stolen. It appears to be made of plastic and not very valuable. \"I'll pay you 2,000 credits now, plus 15,000 on delivery,\" the figure says. After seeing the look on your face he adds, \"It's a collector's item. Will you deliver it or not?\""
        case .sculptureDelivered: "Yet another dark, hooded figure approaches. \"Do you have the action fig- umm, the sculpture?\" You hand it over and hear what sounds very much like a giggle from under the hood. \"I know you were promised 15,000 credits on delivery, but I'm strapped for cash right now. However, I have something better for you. I have an acquaintance who can install hidden compartments in your ship.\" Return with an empty gadget slot when you're ready to have it installed."
        case .sculptureHiddenBays: "You're taken to a warehouse and whisked through the door. A grubby alien of some humanoid species - you're not sure which one - approaches. \"So you're the being who needs Hidden Compartments. Should I install them in your ship?\" (It requires a free gadget slot.)"
        case .princess: "A member of the Royal Family of Galvon has been kidnapped! Princess Ziyal was abducted by men while travelling across the planet. They escaped in a hi-tech ship called the Scorpion. Please rescue her! (You'll need to equip your ship with disruptors to be able to defeat the Scorpion without destroying it.) A ship bristling with weapons was blasting out of the system. It's trajectory before going to warp indicates that its destination was Centauri."
        case .princessCentauri: "A ship had its shields upgraded to Lighting Shields just two days ago. A shipyard worker overheard one of the crew saying they were headed to Inthara."
        case .princessInthara: "Just yesterday a ship was seen in docking bay 327. A trader sold goods to a member of the crew, who was a native of Qonos. It's possible that's where they were going next."
        case .princessQonos: "The Galvonian Ambassador to Qonos approaches you. The Princess needs a ride home. Will you take her? I don't think she'll feel safe with anyone else."
        case .princessQuantum: "His Majesty's Shipyard: Do you want us to install a quantum disruptor on your current ship?"
        case .princessReturned: "The King and Queen are extremely grateful to you for returning their daughter to them. The King says, \"Ziyal is priceless to us, but we feel we must offer you something as a reward. Visit my shipyard captain and he'll install one of our new Quantum Disruptors.\""
        }
    }
    // swiftlint:enable cyclomatic_complexity line_length
}

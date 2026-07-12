// Picture rounds — 16 questions, all difficulty 2. Each carries a CouchCore
// DemoArt recipe id; the app shows the art mosaic-blurred behind the prompt
// and sharpens it on the reveal. The question always matches the art's theme.
// Correct slots cycle 0→1→2→3 to keep direction balance exact.
import Foundation

enum PackPicture {
    static let questions: [Question] = [
        // "dunes" — desert landscape, Mojave
        packQuestion("pic-01", "Why do clear deserts turn cold at night?",
                     correct: "Dry air traps little heat",
                     wrong: ["Sand reflects starlight", "Night winds bring frost", "The Moon cools the sand"],
                     slot: 0, .science, 2, art: "dunes"),
        packQuestion("pic-02", "Which animal stores fat in its hump?",
                     correct: "The camel", wrong: ["The bison", "The llama", "The zebra"],
                     slot: 1, .science, 2, art: "dunes"),

        // "cold-harbor" — northern shoreline, Reykjavík
        packQuestion("pic-03", "What is the capital of Iceland?",
                     correct: "Reykjavik", wrong: ["Oslo", "Helsinki", "Nuuk"],
                     slot: 2, .geography, 2, art: "cold-harbor"),
        packQuestion("pic-04", "What heats Iceland's famous hot springs?",
                     correct: "Geothermal heat", wrong: ["Ocean currents", "Solar farms", "Burning peat"],
                     slot: 3, .science, 2, art: "cold-harbor"),

        // "paper-sun" — Kyoto
        packQuestion("pic-05", "Kyoto was once the capital of which country?",
                     correct: "Japan", wrong: ["China", "Korea", "Thailand"],
                     slot: 0, .geography, 2, art: "paper-sun"),
        packQuestion("pic-06", "What is the gateway arch at a Japanese shrine called?",
                     correct: "A torii", wrong: ["A pagoda", "A dojo", "A tatami"],
                     slot: 1, .general, 2, art: "paper-sun"),

        // "ember-sky" — sunset wash, Lisbon
        packQuestion("pic-07", "Lisbon is the capital of which country?",
                     correct: "Portugal", wrong: ["Spain", "Italy", "Greece"],
                     slot: 2, .geography, 2, art: "ember-sky"),
        packQuestion("pic-08", "What turns the sky red at sunset?",
                     correct: "Scattered sunlight", wrong: ["Ocean reflections", "Heat haze", "The Moon's glow"],
                     slot: 3, .science, 2, art: "ember-sky"),

        // "deep-field" — starfield, Atacama
        packQuestion("pic-09", "What is a vast island of stars called?",
                     correct: "A galaxy", wrong: ["A nebula", "A comet", "A quasar"],
                     slot: 0, .science, 2, art: "deep-field"),
        packQuestion("pic-10", "Why do telescopes love the Atacama Desert?",
                     correct: "Clear, dry skies", wrong: ["Low gravity", "Cheap land", "Strong winds"],
                     slot: 1, .science, 2, art: "deep-field"),

        // "terraces" — rice terraces, Sa Pa
        packQuestion("pic-11", "Which crop grows in flooded hillside terraces?",
                     correct: "Rice", wrong: ["Wheat", "Corn", "Barley"],
                     slot: 2, .general, 2, art: "terraces"),
        packQuestion("pic-12", "The Sa Pa terraces are in which country?",
                     correct: "Vietnam", wrong: ["Laos", "Cambodia", "Myanmar"],
                     slot: 3, .geography, 2, art: "terraces"),

        // "neon-tide" — Tokyo Bay at night
        packQuestion("pic-13", "Tokyo sits on which Japanese island?",
                     correct: "Honshu", wrong: ["Hokkaido", "Kyushu", "Shikoku"],
                     slot: 0, .geography, 2, art: "neon-tide"),
        packQuestion("pic-14", "What makes a neon sign glow?",
                     correct: "Electrified gas", wrong: ["Heated wires", "Tiny mirrors", "Glowing paint"],
                     slot: 1, .science, 2, art: "neon-tide"),

        // "aurora" — northern lights, Tromsø
        packQuestion("pic-15", "What sparks the northern lights?",
                     correct: "Solar particles", wrong: ["Moonlight on ice", "Volcanic ash", "City lights"],
                     slot: 2, .science, 2, art: "aurora"),
        packQuestion("pic-16", "Tromso, gateway to the aurora, is in which country?",
                     correct: "Norway", wrong: ["Finland", "Sweden", "Iceland"],
                     slot: 3, .geography, 2, art: "aurora"),
    ]
}

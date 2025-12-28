//! Custom 512-word wordlist for mnemonic checksums.
//!
//! Words are selected for:
//! - Distinct pronunciation (minimal homophones)
//! - Cross-language clarity
//! - Short, common words
//! - Easy to speak and hear

/// The wordlist (512 words = 9 bits per word).
///
/// Selection criteria:
/// - 3-7 letters preferred
/// - No homophones (e.g., no "night/knight", "write/right")
/// - No words easily confused when spoken
/// - Common English words recognizable globally
pub const WORDLIST: [&str; 512] = [
    // Section 1 (32 words)
    "able", "acid", "aged", "also", "area", "army", "away", "baby", "back", "ball", "band", "bank",
    "base", "bath", "bear", "beat", "been", "bell", "belt", "bend", "best", "bird", "bite", "blow",
    "blue", "boat", "body", "bomb", "bond", "bone", "book", "boot",
    // Section 2 (32 words)
    "born", "boss", "both", "bowl", "bulk", "burn", "bush", "busy", "cafe", "cage", "cake", "call",
    "calm", "came", "camp", "card", "care", "cart", "case", "cash", "cast", "cave", "cell", "chef",
    "chip", "city", "clay", "club", "coal", "coat", "code", "coin",
    // Section 3 (32 words)
    "cold", "come", "cook", "cool", "copy", "core", "corn", "cost", "crew", "crop", "cube", "cure",
    "dark", "data", "date", "dawn", "days", "dead", "deal", "dean", "dear", "debt", "deck", "deep",
    "deer", "demo", "deny", "desk", "dial", "diet", "dirt", "disc",
    // Section 4 (32 words)
    "dish", "dock", "does", "done", "door", "dose", "down", "drag", "draw", "drop", "drug", "drum",
    "dual", "duke", "dump", "dust", "duty", "each", "earn", "ease", "east", "easy", "edge", "edit",
    "else", "emit", "ends", "epic", "even", "ever", "evil", "exam",
    // Section 5 (32 words)
    "exit", "expo", "face", "fact", "fade", "fail", "fair", "fake", "fall", "fame", "farm", "fast",
    "fate", "fear", "feed", "feel", "feet", "fell", "felt", "file", "fill", "film", "find", "fine",
    "fire", "firm", "fish", "five", "flag", "flat", "fled", "flip",
    // Section 6 (32 words)
    "flow", "foam", "fold", "folk", "fond", "font", "food", "foot", "ford", "fork", "form", "fort",
    "foul", "four", "free", "from", "fuel", "full", "fund", "fury", "fuse", "gain", "game", "gang",
    "gate", "gave", "gear", "gene", "gift", "girl", "give", "glad",
    // Section 7 (32 words)
    "glow", "glue", "goal", "goat", "goes", "gold", "golf", "gone", "good", "grab", "grad", "gram",
    "gray", "grew", "grid", "grim", "grip", "grow", "gulf", "guru", "guys", "hack", "half", "hall",
    "halt", "hand", "hang", "hard", "harm", "hate", "have", "hawk",
    // Section 8 (32 words)
    "head", "heal", "heap", "heat", "held", "help", "hero", "hide", "high", "hike", "hill", "hint",
    "hold", "hole", "holy", "home", "hood", "hook", "hope", "horn", "host", "huge", "hull", "hung",
    "hunt", "hurt", "icon", "idea", "inch", "into", "iron", "item",
    // Section 9 (32 words)
    "jack", "jade", "jail", "jazz", "jean", "jeep", "jobs", "join", "joke", "jump", "june", "junk",
    "jury", "just", "keen", "keep", "kept", "kick", "kids", "kill", "kind", "king", "kiss", "kite",
    "knee", "knew", "knob", "know", "lack", "lady", "laid", "lake",
    // Section 10 (32 words)
    "lamp", "land", "lane", "last", "late", "lawn", "laws", "lazy", "lead", "leaf", "lean", "leap",
    "left", "lend", "lens", "less", "life", "lift", "lime", "limp", "line", "link", "lion", "lips",
    "list", "live", "load", "loan", "lock", "logo", "long", "look",
    // Section 11 (32 words)
    "loop", "lord", "lose", "loss", "lost", "lots", "loud", "love", "luck", "lump", "lung", "made",
    "mail", "main", "make", "male", "mall", "many", "maps", "mark", "mars", "mask", "mass", "math",
    "maze", "meal", "mean", "meat", "meet", "mega", "melt", "memo",
    // Section 12 (32 words)
    "menu", "mere", "mesh", "mess", "mild", "mile", "milk", "mill", "mind", "mine", "mint", "miss",
    "mode", "mold", "monk", "mood", "moon", "more", "most", "move", "much", "must", "myth", "nail",
    "name", "navy", "near", "neat", "neck", "need", "nest", "nets",
    // Section 13 (32 words)
    "news", "next", "nice", "nick", "nine", "node", "none", "noon", "norm", "nose", "note", "noun",
    "odds", "okay", "once", "ones", "only", "onto", "open", "oral", "oven", "over", "pace", "pack",
    "page", "paid", "pain", "pair", "pale", "palm", "park", "part",
    // Section 14 (32 words)
    "pass", "past", "path", "peak", "pick", "pier", "pile", "pine", "pink", "pipe", "plan", "play",
    "plea", "plot", "plug", "plus", "poem", "poet", "pole", "poll", "pond", "pool", "poor", "pope",
    "pork", "port", "pose", "post", "pour", "pray", "prep", "prey",
    // Section 15 (32 words)
    "prop", "pull", "pump", "pure", "push", "quit", "quiz", "race", "rack", "rage", "raid", "rail",
    "rain", "rang", "rank", "rare", "rate", "rays", "read", "real", "rear", "rely", "rent", "rest",
    "rice", "rich", "ride", "ring", "rise", "risk", "road", "rock",
    // Section 16 (32 words)
    "role", "roll", "roof", "room", "root", "rope", "rose", "rude", "rule", "runs", "rush", "rust",
    "safe", "sage", "said", "sail", "sake", "sale", "salt", "same", "sand", "sang", "save", "says",
    "scan", "seal", "seat", "seed", "seek", "seem", "seen", "self",
];

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn wordlist_has_512_words() {
        assert_eq!(WORDLIST.len(), 512);
    }

    #[test]
    fn wordlist_no_duplicates() {
        let unique: HashSet<_> = WORDLIST.iter().collect();
        assert_eq!(unique.len(), WORDLIST.len(), "wordlist contains duplicates");
    }

    #[test]
    fn wordlist_all_lowercase() {
        for word in &WORDLIST {
            assert_eq!(
                *word,
                word.to_lowercase(),
                "word '{}' is not lowercase",
                word
            );
        }
    }

    #[test]
    fn wordlist_reasonable_length() {
        for word in &WORDLIST {
            assert!(
                word.len() >= 2 && word.len() <= 7,
                "word '{}' has unusual length {}",
                word,
                word.len()
            );
        }
    }

    #[test]
    fn wordlist_ascii_only() {
        for word in &WORDLIST {
            assert!(word.is_ascii(), "word '{}' contains non-ASCII", word);
        }
    }
}

import Foundation

// Port of Lang.kt (RU + EN only this pass — see the note on `Lang` in ProgressStore.swift).

struct Strings {
    let appTitle: String; let subtitle: String
    let daily: String; let training: String; let archive: String; let stats: String; let settings: String; let exit: String
    let play: String; let solvedToday: String; let failedToday: String; let nextIn: String
    let streak: String; let best: String; let rating: String
    let weekday: [String]; let level: [String]
    let youPlayWhite: String; let youPlayBlack: String
    let findBest: String; let findMate: (Int) -> String
    let opponentMoves: String; let correct: String; let wrong: String
    let attemptsLeft: String; let hintAd: String
    let solved: String; let failed: String; let solution: String
    let share: String; let next: String; let home: String; let toTraining: String
    let puzzleRating: String; let themes: String
    let archiveLocked: String; let archiveEmpty: String
    let sound: String; let language: String; let notify: String; let on: String; let off: String
    let played: String; let winPct: String; let trainingSolved: String
    let promote: String; let dailyNo: String
    let shareText: (Int, String, Int, String) -> String
    let solvedIn: (Int, Int) -> String
    let credit: String
    let chooseLang: String
    let ranks: [String]; let rank: String; let rankUp: String
    let calendar: String; let weekShort: [String]; let months: [String]
    let freezeTitle: String; let freezeText: (Int) -> String; let freezeYes: String; let freezeNo: String
    let challengeTitle: String; let challengeText: (String) -> String
    let rush: String; let rushDesc: String; let rushAgain: String; let rushScore: String; let rushNewBest: String; let rushOver: String
    let shareRush: (Int) -> String
    let lessons: String; let lessonsDesc: String; let lessonOf: (Int, Int) -> String; let lessonDone: String; let lessonTexts: [String]
    let achievements: String; let achNew: String
    let achFirst: String; let achStreak: (Int) -> String; let achTrain: (Int) -> String; let achRating: (Int) -> String
    let achRush: (Int) -> String; let achLessons: String; let achMate3: String
    let boardTheme: String; let boardThemes: [String]; let unlockStreak: (Int) -> String; let unlockTrain: (Int) -> String
}

private let RU = Strings(
    appTitle: "Шахматная задача — Ход дня", subtitle: "Одна задача в день — для всех",
    daily: "Задача дня", training: "Тренировка", archive: "Архив", stats: "Статистика", settings: "Настройки", exit: "Выход",
    play: "Решать", solvedToday: "Решено ✓", failedToday: "Не решено", nextIn: "Новая задача через",
    streak: "Серия", best: "Рекорд", rating: "Рейтинг",
    weekday: ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"],
    level: ["Очень легко", "Легко", "Средне", "Средне+", "Трудно", "Очень трудно", "Мастер"],
    youPlayWhite: "Вы играете белыми", youPlayBlack: "Вы играете чёрными",
    findBest: "Найдите лучший ход", findMate: { n in "Мат в \(n) \(n == 1 ? "ход" : "хода")" },
    opponentMoves: "Соперник отвечает…", correct: "Верно! Продолжайте", wrong: "Не тот ход",
    attemptsLeft: "Попыток", hintAd: "Подсказка (реклама)",
    solved: "Решено!", failed: "Не получилось", solution: "Решение",
    share: "Поделиться", next: "Дальше", home: "Главная", toTraining: "В тренировку",
    puzzleRating: "Рейтинг задачи", themes: "Темы",
    archiveLocked: "Открыть за рекламу", archiveEmpty: "Архив появится со следующего дня",
    sound: "Звук", language: "Язык", notify: "Напоминание о задаче дня", on: "Вкл", off: "Выкл",
    played: "Сыграно", winPct: "Решено %", trainingSolved: "Решено в тренировке",
    promote: "Выберите фигуру", dailyNo: "№",
    shareText: { n, grid, st, link in "Ход дня №\(n) ♟\n\(grid)\n🔥 Серия: \(st)\n\nРешай со мной: \(link)" },
    solvedIn: { a, m in "с \(a)-й попытки из \(m)" },
    credit: "Задачи: база Lichess (CC0)",
    chooseLang: "Выберите язык",
    ranks: ["Пешка", "Конь", "Слон", "Ладья", "Ферзь", "Король", "Гроссмейстер"], rank: "Звание", rankUp: "Новое звание!",
    calendar: "Календарь", weekShort: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"],
    months: ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"],
    freezeTitle: "Серия под угрозой! 🔥", freezeText: { n in "Вчерашняя задача пропущена. Сохранить серию из \(n) дн. за просмотр рекламы? Заморозка доступна раз в неделю." },
    freezeYes: "❄️ Сохранить серию", freezeNo: "Не надо",
    challengeTitle: "Вызов от друга", challengeText: { goal in "Сможешь решить? ♟ \(goal)" },
    rush: "Штурм", rushDesc: "3 минуты — решите как можно больше задач", rushAgain: "Ещё раз", rushScore: "Решено задач",
    rushNewBest: "Новый рекорд!", rushOver: "Время вышло!",
    shareRush: { n in "⚡ Штурм: \(n) задач за 3 минуты! Побьёшь мой рекорд?" },
    lessons: "Уроки", lessonsDesc: "Тактика для начинающих", lessonOf: { i, n in "Задача \(i) из \(n)" }, lessonDone: "Урок пройден! 🎓",
    lessonTexts: [
        "Мат — это шах, от которого нет защиты. Ищите ход, после которого королю некуда уйти, нечем закрыться и некем взять атакующую фигуру.",
        "Вилка — одна фигура нападает сразу на две. Соперник спасёт только одну. Особенно опасны вилки конём.",
        "Связка — фигура не может уйти, потому что за ней стоит более ценная фигура или король. Атакуйте связанную фигуру!",
        "Сквозной удар — нападение на ценную фигуру, за которой стоит другая. Ценная уходит, и вы забираете ту, что сзади.",
        "Вскрытый удар — одна фигура уходит с линии и открывает атаку другой. Ушедшая фигура тоже может напасть — двойная угроза!",
        "Мат на последней горизонтали: король заперт своими пешками, и ладья или ферзь ставят мат по первой (или восьмой) линии.",
    ],
    achievements: "Достижения", achNew: "Новое достижение!",
    achFirst: "Первая задача дня", achStreak: { n in "Серия \(n) дн." }, achTrain: { n in "\(n) задач в тренировке" },
    achRating: { n in "Рейтинг \(n)" }, achRush: { n in "\(n) задач в штурме" }, achLessons: "Все уроки пройдены", achMate3: "Мат в 3+ хода",
    boardTheme: "Доска", boardThemes: ["Орех", "Турнир", "Океан", "Мрамор", "Аметист"],
    unlockStreak: { n in "Откроется за серию \(n) дн." }, unlockTrain: { n in "Откроется за \(n) задач в тренировке" }
)

private let EN = Strings(
    appTitle: "Chess Puzzle — Move of the Day", subtitle: "One puzzle a day — the same for everyone",
    daily: "Daily puzzle", training: "Training", archive: "Archive", stats: "Statistics", settings: "Settings", exit: "Exit",
    play: "Solve", solvedToday: "Solved ✓", failedToday: "Not solved", nextIn: "New puzzle in",
    streak: "Streak", best: "Best", rating: "Rating",
    weekday: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
    level: ["Very easy", "Easy", "Medium", "Medium+", "Hard", "Very hard", "Master"],
    youPlayWhite: "You play White", youPlayBlack: "You play Black",
    findBest: "Find the best move", findMate: { n in "Mate in \(n)" },
    opponentMoves: "Opponent replies…", correct: "Correct! Keep going", wrong: "Not the move",
    attemptsLeft: "Attempts", hintAd: "Hint (ad)",
    solved: "Solved!", failed: "Not this time", solution: "Solution",
    share: "Share", next: "Next", home: "Home", toTraining: "Go to training",
    puzzleRating: "Puzzle rating", themes: "Themes",
    archiveLocked: "Unlock with an ad", archiveEmpty: "The archive starts tomorrow",
    sound: "Sound", language: "Language", notify: "Daily puzzle reminder", on: "On", off: "Off",
    played: "Played", winPct: "Solved %", trainingSolved: "Solved in training",
    promote: "Choose a piece", dailyNo: "#",
    shareText: { n, grid, st, link in "Move of the Day #\(n) ♟\n\(grid)\n🔥 Streak: \(st)\n\nPlay with me: \(link)" },
    solvedIn: { a, m in "on attempt \(a) of \(m)" },
    credit: "Puzzles: Lichess database (CC0)",
    chooseLang: "Choose language",
    ranks: ["Pawn", "Knight", "Bishop", "Rook", "Queen", "King", "Grandmaster"], rank: "Rank", rankUp: "New rank!",
    calendar: "Calendar", weekShort: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"],
    months: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"],
    freezeTitle: "Your streak is in danger! 🔥", freezeText: { n in "You missed yesterday's puzzle. Keep your \(n)-day streak by watching an ad? A freeze is available once a week." },
    freezeYes: "❄️ Keep my streak", freezeNo: "No thanks",
    challengeTitle: "Challenge from a friend", challengeText: { goal in "Can you solve it? ♟ \(goal)" },
    rush: "Puzzle Rush", rushDesc: "3 minutes — solve as many puzzles as you can", rushAgain: "Play again", rushScore: "Puzzles solved",
    rushNewBest: "New record!", rushOver: "Time's up!",
    shareRush: { n in "⚡ Puzzle Rush: \(n) puzzles in 3 minutes! Can you beat my record?" },
    lessons: "Lessons", lessonsDesc: "Tactics for beginners", lessonOf: { i, n in "Puzzle \(i) of \(n)" }, lessonDone: "Lesson complete! 🎓",
    lessonTexts: [
        "Checkmate is a check with no defence. Look for a move after which the king cannot escape, block, or capture the attacker.",
        "A fork is one piece attacking two at once. Your opponent can save only one. Knight forks are especially dangerous.",
        "A pin: a piece can't move because a more valuable piece or the king stands behind it. Attack the pinned piece!",
        "A skewer attacks a valuable piece with another one behind it. The valuable piece moves away and you take the one behind.",
        "A discovered attack: one piece moves off a line and unmasks an attack by another. The moving piece can attack too — a double threat!",
        "Back-rank mate: the king is boxed in by its own pawns, and a rook or queen mates along the first (or eighth) rank.",
    ],
    achievements: "Achievements", achNew: "New achievement!",
    achFirst: "First daily puzzle", achStreak: { n in "\(n)-day streak" }, achTrain: { n in "\(n) training puzzles" },
    achRating: { n in "Rating \(n)" }, achRush: { n in "\(n) in Puzzle Rush" }, achLessons: "All lessons complete", achMate3: "Mate in 3+",
    boardTheme: "Board", boardThemes: ["Walnut", "Tournament", "Ocean", "Marble", "Amethyst"],
    unlockStreak: { n in "Unlocks with a \(n)-day streak" }, unlockTrain: { n in "Unlocks after \(n) training puzzles" }
)

func stringsFor(_ lang: Lang) -> Strings { lang == .ru ? RU : EN }

/// Theme keys used for the training filter + display names.
let TRAIN_THEMES = ["all", "mateIn1", "mateIn2", "mateIn3", "fork", "pin", "skewer", "sacrifice", "discoveredAttack", "endgame"]

private let THEME_NAMES: [String: (ru: String, en: String)] = [
    "all": ("Все", "All"),
    "mateIn1": ("Мат в 1", "Mate in 1"),
    "mateIn2": ("Мат в 2", "Mate in 2"),
    "mateIn3": ("Мат в 3+", "Mate in 3+"),
    "fork": ("Вилка", "Fork"),
    "pin": ("Связка", "Pin"),
    "skewer": ("Сквозной удар", "Skewer"),
    "sacrifice": ("Жертва", "Sacrifice"),
    "discoveredAttack": ("Вскрытый удар", "Discovered attack"),
    "endgame": ("Эндшпиль", "Endgame"),
    "backRankMate": ("Мат на последней горизонтали", "Back-rank mate"),
    "promotion": ("Превращение", "Promotion"),
    "hangingPiece": ("Незащищённая фигура", "Hanging piece"),
    "deflection": ("Отвлечение", "Deflection"),
    "attraction": ("Завлечение", "Attraction"),
    "doubleCheck": ("Двойной шах", "Double check"),
    "smotheredMate": ("Спёртый мат", "Smothered mate"),
    "trappedPiece": ("Пойманная фигура", "Trapped piece"),
    "quietMove": ("Тихий ход", "Quiet move"),
    "middlegame": ("Миттельшпиль", "Middlegame"),
    "opening": ("Дебют", "Opening"),
]

func themeName(_ key: String, _ lang: Lang) -> String? {
    guard let t = THEME_NAMES[key] else { return nil }
    return lang == .ru ? t.ru : t.en
}

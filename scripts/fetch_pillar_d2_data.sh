#!/bin/bash
# Pillar D2: pull demo-portal tables from dev EC2 (NOD_eyesee.Demo_*).
# Drops IP / user-agent fields for privacy; keeps nicknames (user-chosen handles).
set -e
PEM="/Users/josiahzacharias/Library/Mobile Documents/com~apple~CloudDocs/School/UWB/CSS 595 (Final Project)/AWS/Key Pair/josiah-dev-key.pem"
EC2="ec2-user@13.222.3.49"
DEST="/Users/josiahzacharias/Library/Mobile Documents/com~apple~CloudDocs/School/UWB/CSS 595 (Final Project)/Final Paper/RDS Data/data/pillar_d2"
mkdir -p "$DEST"

run_query() {
    local QUERY="$1"
    ssh -i "$PEM" -o ConnectTimeout=10 "$EC2" \
        "DBHOST=\$(grep '^DB_HOST=' /var/www/.env | cut -d= -f2); \
         DBUSER=\$(grep '^DB_USER=' /var/www/.env | cut -d= -f2); \
         DBPASS=\$(grep '^DB_PASS=' /var/www/.env | cut -d= -f2); \
         mysql -h \$DBHOST -u \$DBUSER -p\$DBPASS NOD_eyesee --batch --silent --raw -e \"$QUERY\" 2>/dev/null"
}

# Pre-fetch all data once via SSH (faster than 6 SSH calls)
ALL=$(ssh -i "$PEM" -o ConnectTimeout=10 "$EC2" "DBHOST=\$(grep '^DB_HOST=' /var/www/.env | cut -d= -f2); DBUSER=\$(grep '^DB_USER=' /var/www/.env | cut -d= -f2); DBPASS=\$(grep '^DB_PASS=' /var/www/.env | cut -d= -f2); \
mysql -h \$DBHOST -u \$DBUSER -p\$DBPASS NOD_eyesee --batch --silent --raw <<EOF 2>/dev/null
SELECT 'USERS' AS marker;
SELECT UserID, Nickname, Created, LastVisit, AccountID FROM Demo_Users;
SELECT 'SESSIONS' AS marker;
SELECT SessionID, UserID, GameName, Duration, StartTime, EndTime FROM Demo_Sessions;
SELECT 'CHALLENGES' AS marker;
SELECT ChallengeID, RoomCode, CreatorNickname, JoinerNickname, GameID, MapSize, GameTheme, GameMode, Status, CreatedAt, PairedAt, FinishedAt FROM Demo_Challenges;
SELECT 'RESULTS' AS marker;
SELECT ResultID, ChallengeID, RoomCode, Nickname, LevelNum, GridSize, Score, HolesFilled, TotalHoles, TimeUsed, Completed, Won, LevelsWon, TotalScore, TotalTime, CreatedAt FROM Demo_Challenge_Results;
SELECT 'FEEDBACK' AS marker;
SELECT FeedbackID, UserID, GameName, FeedbackType, Rating, REPLACE(REPLACE(IFNULL(Comment,''),CHAR(10),' '),',',';') AS Comment, Timestamp FROM Demo_Feedback;
SELECT 'SURVEY' AS marker;
SELECT SurveyID, UserID, GameName, Q1_Ease, Q2_Enjoyment, Q3_Reuse, Q4_Visual, REPLACE(REPLACE(IFNULL(Q5_Comment,''),CHAR(10),' '),',',';') AS Q5_Comment, Timestamp FROM Demo_Survey;
EOF")

# Split the output by markers and write CSVs
python3 <<PYEOF
import re

raw = '''$ALL'''
sections = re.split(r'^marker\nUSERS\n|^marker\nSESSIONS\n|^marker\nCHALLENGES\n|^marker\nRESULTS\n|^marker\nFEEDBACK\n|^marker\nSURVEY\n', raw, flags=re.MULTILINE)
PYEOF

# Simpler: pull each table individually (small data, low cost)
echo "Fetching Demo_Users..."
{
    echo "UserID,Nickname,Created,LastVisit,AccountID"
    run_query "SELECT UserID, Nickname, Created, LastVisit, IFNULL(AccountID,'') FROM Demo_Users ORDER BY UserID" | tr '\t' ','
} > "$DEST/demo_users.csv"
echo "  -> $DEST/demo_users.csv ($(wc -l < "$DEST/demo_users.csv") lines)"

echo "Fetching Demo_Sessions (with GameData JSON parsed)..."
{
    echo "SessionID,UserID,GameName,Duration,StartTime,EndTime,accuracy,highestLevel,levelsPlayed,totalCorrect,totalTrials,startVergence,endVergence,startDifficulty,endDifficulty"
    run_query "SELECT SessionID, IFNULL(UserID,''), GameName, IFNULL(Duration,0), StartTime, IFNULL(EndTime,''),
        IFNULL(JSON_EXTRACT(GameData,'$.accuracy'),''),
        IFNULL(JSON_EXTRACT(GameData,'$.highestLevel'),''),
        IFNULL(JSON_EXTRACT(GameData,'$.levelsPlayed'),''),
        IFNULL(JSON_EXTRACT(GameData,'$.totalCorrect'),''),
        IFNULL(JSON_EXTRACT(GameData,'$.totalTrials'),''),
        IFNULL(JSON_EXTRACT(GameData,'$.startVergence'),''),
        IFNULL(JSON_EXTRACT(GameData,'$.endVergence'),''),
        IFNULL(JSON_EXTRACT(GameData,'$.startDifficulty'),''),
        IFNULL(JSON_EXTRACT(GameData,'$.endDifficulty'),'')
        FROM Demo_Sessions ORDER BY StartTime" | tr '\t' ','
} > "$DEST/demo_sessions.csv"
echo "  -> $DEST/demo_sessions.csv ($(wc -l < "$DEST/demo_sessions.csv") lines)"

echo "Fetching Demo_Challenges..."
{
    echo "ChallengeID,RoomCode,CreatorNickname,JoinerNickname,GameID,MapSize,GameTheme,GameMode,Status,CreatedAt,PairedAt,FinishedAt"
    run_query "SELECT ChallengeID, RoomCode, CreatorNickname, IFNULL(JoinerNickname,''), GameID, MapSize, IFNULL(GameTheme,''), IFNULL(GameMode,''), Status, CreatedAt, IFNULL(PairedAt,''), IFNULL(FinishedAt,'') FROM Demo_Challenges ORDER BY CreatedAt" | tr '\t' ','
} > "$DEST/demo_challenges.csv"
echo "  -> $DEST/demo_challenges.csv ($(wc -l < "$DEST/demo_challenges.csv") lines)"

echo "Fetching Demo_Challenge_Results..."
{
    echo "ResultID,ChallengeID,RoomCode,Nickname,LevelNum,GridSize,Score,HolesFilled,TotalHoles,TimeUsed,Completed,Won,LevelsWon,TotalScore,TotalTime,CreatedAt"
    run_query "SELECT ResultID, ChallengeID, RoomCode, IFNULL(Nickname,''), LevelNum, IFNULL(GridSize,''), Score, HolesFilled, TotalHoles, TimeUsed, Completed, Won, IFNULL(LevelsWon,''), IFNULL(TotalScore,''), IFNULL(TotalTime,''), CreatedAt FROM Demo_Challenge_Results ORDER BY CreatedAt" | tr '\t' ','
} > "$DEST/demo_challenge_results.csv"
echo "  -> $DEST/demo_challenge_results.csv ($(wc -l < "$DEST/demo_challenge_results.csv") lines)"

echo "Fetching Demo_Feedback..."
{
    echo "FeedbackID,UserID,GameName,FeedbackType,Rating,Comment,Timestamp"
    run_query "SELECT FeedbackID, IFNULL(UserID,''), IFNULL(GameName,''), IFNULL(FeedbackType,''), IFNULL(Rating,''), REPLACE(REPLACE(IFNULL(Comment,''),CHAR(10),' '),',',';'), Timestamp FROM Demo_Feedback ORDER BY Timestamp" | tr '\t' ','
} > "$DEST/demo_feedback.csv"
echo "  -> $DEST/demo_feedback.csv ($(wc -l < "$DEST/demo_feedback.csv") lines)"

echo "Fetching Demo_Survey..."
{
    echo "SurveyID,UserID,GameName,Q1_Ease,Q2_Enjoyment,Q3_Reuse,Q4_Visual,Q5_Comment,Timestamp"
    run_query "SELECT SurveyID, IFNULL(UserID,''), GameName, IFNULL(Q1_Ease,''), IFNULL(Q2_Enjoyment,''), IFNULL(Q3_Reuse,''), IFNULL(Q4_Visual,''), REPLACE(REPLACE(IFNULL(Q5_Comment,''),CHAR(10),' '),',',';'), Timestamp FROM Demo_Survey ORDER BY Timestamp" | tr '\t' ','
} > "$DEST/demo_survey.csv"
echo "  -> $DEST/demo_survey.csv ($(wc -l < "$DEST/demo_survey.csv") lines)"

echo "Done."

#!/bin/bash
# Fetch Pillar C adoption data from dev EC2 and write CSVs locally.
# Re-run any time you want fresh data.
set -e
PEM="/Users/josiahzacharias/Library/Mobile Documents/com~apple~CloudDocs/School/UWB/CSS 595 (Final Project)/AWS/Key Pair/josiah-dev-key.pem"
EC2="ec2-user@13.222.3.49"
DEST="/Users/josiahzacharias/Library/Mobile Documents/com~apple~CloudDocs/School/UWB/CSS 595 (Final Project)/Final Paper/RDS Data/data/pillar_c"

run_query() {
    local QUERY="$1"
    ssh -i "$PEM" -o ConnectTimeout=10 "$EC2" \
        "DBHOST=\$(grep '^DB_HOST=' /var/www/.env | cut -d= -f2); \
         DBUSER=\$(grep '^DB_USER=' /var/www/.env | cut -d= -f2); \
         DBPASS=\$(grep '^DB_PASS=' /var/www/.env | cut -d= -f2); \
         mysql -h \$DBHOST -u \$DBUSER -p\$DBPASS NOD_subscribers --batch --silent --raw -e \"$QUERY\" 2>/dev/null"
}

echo "Fetching Professional_Activity..."
{
    echo "ActivityID,TeacherID,InstID,Interface,PageName,Action,Detail,Duration,CreatedAt"
    run_query "SELECT ActivityID, TeacherID, InstID, Interface, PageName, Action, REPLACE(REPLACE(IFNULL(Detail,''), ',', ';'), CHAR(10), ' '), IFNULL(Duration,''), CreatedAt FROM Professional_Activity ORDER BY CreatedAt" \
        | tr '\t' ','
} > "$DEST/professional_activity.csv"
echo "  -> $DEST/professional_activity.csv ($(wc -l < "$DEST/professional_activity.csv") lines)"

echo "Fetching Clinician_Study..."
{
    echo "StudyID,TeacherID,StudyGroup,IsResearchAdmin,AssignedBy,EnrolledAt"
    run_query "SELECT StudyID, TeacherID, StudyGroup, IsResearchAdmin, IFNULL(AssignedBy,''), EnrolledAt FROM Clinician_Study ORDER BY EnrolledAt" | tr '\t' ','
} > "$DEST/clinician_study.csv"
echo "  -> $DEST/clinician_study.csv ($(wc -l < "$DEST/clinician_study.csv") lines)"

echo "Fetching Student_Study..."
{
    echo "StudyID,StudentID,StudyGroup,AssignedBy,EnrolledAt"
    run_query "SELECT StudyID, StudentID, StudyGroup, IFNULL(AssignedBy,''), EnrolledAt FROM Student_Study ORDER BY EnrolledAt" | tr '\t' ','
} > "$DEST/student_study.csv"
echo "  -> $DEST/student_study.csv ($(wc -l < "$DEST/student_study.csv") lines)"

echo "Done."

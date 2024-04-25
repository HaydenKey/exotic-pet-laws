from bs4 import BeautifulSoup
import json

# Not my prettiest work, but I just wanted it to work

#############################
# PART 1: Load HTML content #
#############################
with open('../data/legal-data-to-be-parsed.html', 'r') as file:
    html_content = file.read()


def parse_html_table(html_content):
    soup = BeautifulSoup(html_content, 'html.parser')
    state_data_list = []

    for row in soup.find_all('tr'):
        state_data = {}

        # Extracting state name
        th_tag = row.find('th')
        if th_tag:
            state_name = th_tag.text.strip()
            state_data['state'] = state_name
        else:
            continue  # Skip this row if <th> tag is not found

        # Extracting Exotic Animals That Are Legal to Own
        legal_to_own = extract_list_from_td(row.find_all('td')[0])
        state_data['legal_to_own'] = legal_to_own

        # Extracting Exotic Animals That Are Illegal to Own
        illegal_to_own = extract_list_from_td(row.find_all('td')[1])
        state_data['illegal_to_own'] = illegal_to_own

        # Extracting Special Permits or Licenses Required
        permits_required = extract_list_from_td(row.find_all('td')[2])
        state_data['permits_required'] = permits_required

        # Extracting State Statutes (Laws)
        statutes = extract_statutes(row.find_all('td')[3])
        state_data['state_statutes'] = statutes

        state_data_list.append(state_data)

    return state_data_list


def extract_list_from_td(td):
    ul = td.find('ul')
    if ul:
        return [li.text.strip() for li in ul.find_all('li')]
    else:
        return [td.text.strip()]


def extract_statutes(td):
    statutes = []
    for a in td.find_all('a'):
        title = a.get('title', '')
        url = a['href']
        statutes.append({'title': title, 'url': url})
    return statutes


# Parse HTML table and extract data
reformatted_html_data = parse_html_table(html_content)

# Write the extracted data to a JSON file
with open("../data/exotic_animals_legality_data.json", 'w') as json_file:
    json.dump(reformatted_html_data, json_file, indent=4)


##########################################
# PART 2: FORMAT JSON DATA FOR DYNAMO DB #
##########################################

with open("../data/exotic_animals_legality_data.json", 'r') as json_file_read_only:
    exotic_animals_legality_json_data = json.load(json_file_read_only)

json_file_read_only.close()

# it seems the AWS command line can't handle more than 25 of these at a time, so I am doing them 10 at a time using this
# aws dynamodb batch-write-item --request-items file://data/exotic_animals_legality_data.json
start_state_index = 40  # State index starts from 0
end_state_index = 50  # Inclusive index

new_json_data_list = []

# Modify the specified attributes and add "SS" suffix
for index, us_state in enumerate(exotic_animals_legality_json_data):
    if start_state_index <= index <= end_state_index:
        # Modify legal_to_own
        us_state['state'] = {"S": us_state['state']}

        # Modify legal_to_own
        us_state['legal_to_own'] = {"SS": list(set(us_state['legal_to_own']))}

        # Modify illegal_to_own
        us_state['illegal_to_own'] = {"SS": list(set(us_state['illegal_to_own']))}

        # Modify permits_required
        us_state['permits_required'] = {"SS": us_state['permits_required']}

        # Modify state_statutes
        formatted_state_statutes = {}
        for statute in us_state['state_statutes']:
            if not statute["title"]:
                statute["title"] = "Link"
            formatted_statute = {
                "title": {"S": statute["title"]},
                "url": {"S": statute["url"]}
            }
            formatted_state_statutes[statute["title"]] = {"M": formatted_statute}

        us_state['state_statutes'] = {"M": formatted_state_statutes}

        new_json_data_list.append({"PutRequest": {"Item": us_state}})

exotic_animals_legality_json_data = {
        "exotic_animals_legality_table": new_json_data_list
}

# Write the modified data back to a JSON file
with open("../data/exotic_animals_legality_data.json", 'w') as file:
    json.dump(exotic_animals_legality_json_data, file, indent=4)

file.close()

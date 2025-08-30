import requests
from bs4 import BeautifulSoup

# Make an HTTP GET request
url = "https://example.com"
response = requests.get(url)

# Check if the request was successful
if response.status_code == 200:
    # Parse the HTML content
    soup = BeautifulSoup(response.text, 'html.parser')
    
    # Find all paragraph tags
    paragraphs = soup.find_all('p')
    
    # Print the text of each paragraph
    for p in paragraphs:
        print(p.text)
else:
    print(f"Failed to retrieve the webpage. Status code: {response.status_code}")

# Example of API interaction
api_url = "https://api.example.com/data"
api_key = "your_api_key_here"

# Make a GET request to the API with authentication
api_response = requests.get(api_url, headers={"Authorization": f"Bearer {api_key}"})

if api_response.status_code == 200:
    # Parse the JSON response
    data = api_response.json()
    print(data)
else:
    print(f"API request failed. Status code: {api_response.status_code}")
